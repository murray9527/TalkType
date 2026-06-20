import Foundation

/// Qwen-ASR WebSocket client — VAD mode with automatic utterance detection.
/// Audio is streamed continuously; the server detects voice activity and
/// sends .text events (streaming partial) and .completed events (utterance finalized).
actor RemoteASREngine {

    struct Config: Sendable {
        var baseURL: String
        var apiKey: String
        var model: String
        var corpusText: String = ""   // contextual biasing text (up to 10000 tokens)
    }

    private var config: Config
    private var urlSession: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sessionReady = false
    private var audioChunkCount = 0
    private var totalAudioBytes = 0

    // Per-commit tracking
    private var commitContinuations: [CheckedContinuation<String, Error>] = []
    private var finishContinuation: CheckedContinuation<String, Error>?

    /// Called on each .completed event (utterance finalized in VAD mode, or after commit in manual mode).
    private var onPartialTranscript: (@Sendable (String) -> Void)?

    func setPartialTranscriptHandler(_ handler: (@Sendable (String) -> Void)?) {
        onPartialTranscript = handler
    }

    /// Called on each .text event (streaming partial result with text+stash, VAD mode only).
    private var onStreamingText: (@Sendable (String) -> Void)?

    func setStreamingTextHandler(_ handler: (@Sendable (String) -> Void)?) {
        onStreamingText = handler
    }

    /// Called when emotion is detected in a transcription event.
    private var onEmotionDetected: (@Sendable (ASREmotion) -> Void)?

    func setEmotionHandler(_ handler: (@Sendable (ASREmotion) -> Void)?) {
        onEmotionDetected = handler
    }

    init(config: Config = Config(baseURL: "", apiKey: "", model: "")) {
        self.config = config
        self.urlSession = URLSession(configuration: .default)
    }

    func updateConfig(_ newConfig: Config) {
        config = newConfig
    }

    // MARK: - Session Lifecycle

    func startSession(language: String) async throws {
        guard !config.baseURL.isEmpty, !config.apiKey.isEmpty, !config.model.isEmpty else {
            throw RemoteASRError.notConfigured
        }

        var urlStr = config.baseURL
        urlStr += (urlStr.contains("?") ? "&" : "?") + "model=" + config.model.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

        guard let url = URL(string: urlStr) else {
            throw RemoteASRError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let task = urlSession.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        audioChunkCount = 0
        totalAudioBytes = 0
        sessionReady = false
        commitContinuations = []
        finishContinuation = nil

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        try await sendSessionUpdate(language: language)
        sessionReady = true
        print("[QwenASR] Session started (manual mode, periodic commit)")
    }

    func sendAudioChunk(samples: [Float]) async {
        guard let task = webSocketTask, sessionReady else { return }

        let pcmData = float32ToInt16PCM(samples)
        let base64 = pcmData.base64EncodedString()
        if audioChunkCount == 0 {
            print("[QwenASR] First chunk: \(samples.count) float32 → \(pcmData.count) int16 bytes")
        }
        audioChunkCount += 1
        totalAudioBytes += pcmData.count

        let event: [String: Any] = [
            "event_id": "audio_\(UUID().uuidString.prefix(8))",
            "type": "input_audio_buffer.append",
            "audio": base64
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: event),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        try? await task.send(.string(jsonString))
    }

    /// Commits the buffered audio for incremental transcription.
    /// Returns the transcription for the committed buffer.
    func commit() async throws -> String {
        guard let task = webSocketTask, sessionReady else {
            throw RemoteASRError.notConfigured
        }

        let eid = "commit_\(UUID().uuidString.prefix(8))"
        let commitEvent: [String: Any] = [
            "event_id": eid,
            "type": "input_audio_buffer.commit"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: commitEvent),
              let str = String(data: data, encoding: .utf8) else {
            throw RemoteASRError.invalidResponse
        }

        print("[QwenASR] Commit \(eid) — \(audioChunkCount) chunks, \(totalAudioBytes) bytes")
        try await task.send(.string(str))

        return try await withCheckedThrowingContinuation { continuation in
            commitContinuations.append(continuation)
        }
    }

    /// Send session.finish to get the complete corrected transcript.
    /// In VAD mode the server manages utterance boundaries automatically,
    /// so no manual commit is needed — remaining audio is processed on finish.
    func finishSession() async throws -> String {
        guard let task = webSocketTask, sessionReady else {
            throw RemoteASRError.notConfigured
        }

        print("[QwenASR] Finishing — \(audioChunkCount) chunks, \(totalAudioBytes) bytes")

        // Send session.finish — server processes remaining audio and returns full transcript
        let finishEvent: [String: Any] = [
            "event_id": "finish_\(UUID().uuidString.prefix(8))",
            "type": "session.finish"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: finishEvent),
           let str = String(data: data, encoding: .utf8) {
            try await task.send(.string(str))
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.finishContinuation = continuation
        }
    }

    func cancelSession() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        for c in commitContinuations {
            c.resume(throwing: RemoteASRError.cancelled)
        }
        commitContinuations = []
        finishContinuation?.resume(throwing: RemoteASRError.cancelled)
        finishContinuation = nil
        sessionReady = false
    }

    // MARK: - Session Configuration

    private func sendSessionUpdate(language: String) async throws {
        var session: [String: Any] = [
            "modalities": ["text"],
            "input_audio_format": "pcm",
            "sample_rate": 16000,
            "turn_detection": [
                "type": "server_vad",
                "silence_duration_ms": 500
            ]
        ]
        // Only specify language when not "auto" — server auto-detects when omitted
        if language != "auto" {
            session["input_audio_transcription"] = ["language": language]
        }
        // Contextual biasing — helps improve accuracy for specific terms (names, jargon)
        if !config.corpusText.isEmpty {
            session["corpus_text"] = config.corpusText
        }

        let event: [String: Any] = [
            "event_id": "session_update_\(UUID().uuidString.prefix(8))",
            "type": "session.update",
            "session": session
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: event),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw RemoteASRError.invalidResponse
        }

        print("[QwenASR] session.update: \(jsonString)")
        try await webSocketTask?.send(.string(jsonString))
    }

    // MARK: - Receive Loop

    private func receiveLoop() async {
        while let task = webSocketTask, !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    print("[QwenASR] ← \(text.prefix(200))")
                    await handleServerEvent(text)
                case .data:
                    break
                @unknown default:
                    break
                }
            } catch {
                print("[QwenASR] Receive error (\(audioChunkCount) chunks): \(error)")
                let err = error
                for c in commitContinuations { c.resume(throwing: err) }
                commitContinuations = []
                finishContinuation?.resume(throwing: err)
                finishContinuation = nil
                return
            }
        }
    }

    private func handleServerEvent(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "session.updated":
            print("[QwenASR] Session configured (VAD mode)")

        case "input_audio_buffer.committed":
            print("[QwenASR] Buffer committed by server")

        case "conversation.item.input_audio_transcription.text":
            // Streaming partial result (VAD mode): text = confirmed prefix, stash = speculative suffix
            let text = json["text"] as? String ?? ""
            let stash = json["stash"] as? String ?? ""
            let display = text + stash
            onStreamingText?(display)

            // Emotion may also appear in streaming events
            if let emotionStr = json["emotion"] as? String,
               let emotion = ASREmotion(rawValue: emotionStr.lowercased()) {
                onEmotionDetected?(emotion)
            }

        case "conversation.item.input_audio_transcription.completed":
            if let t = json["transcript"] as? String {
                print("[QwenASR] Transcript: '\(t)'")
                onPartialTranscript?(t)

                // Parse emotion if available
                if let emotionStr = json["emotion"] as? String,
                   let emotion = ASREmotion(rawValue: emotionStr.lowercased()) {
                    print("[QwenASR] Emotion detected: \(emotionStr)")
                    onEmotionDetected?(emotion)
                }

                // Resume the oldest waiting commit continuation
                if let first = commitContinuations.first {
                    first.resume(returning: t)
                    commitContinuations.removeFirst()
                }
            }

        case "session.finished":
            let accumulated = json["transcript"] as? String ?? ""
            print("[QwenASR] Session finished — '\(accumulated)'")
            finishContinuation?.resume(returning: accumulated)
            finishContinuation = nil

        case "error":
            let msg = (json["error"] as? [String: Any])?["message"] as? String
                ?? (json["error"] as? [String: Any])?["code"] as? String
                ?? "Unknown error"
            print("[QwenASR] Server error: \(msg)")
            print("[QwenASR] Raw: \(text)")
            let err = RemoteASRError.serverError(msg)
            if let first = commitContinuations.first {
                first.resume(throwing: err)
                commitContinuations.removeFirst()
            }
            finishContinuation?.resume(throwing: err)
            finishContinuation = nil

        default:
            print("[QwenASR] Unhandled '\(type)': \(text.prefix(200))")
        }
    }

    // MARK: - Audio Conversion

    private func float32ToInt16PCM(_ samples: [Float]) -> Data {
        var int16Samples = [Int16](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let clamped = max(-1.0, min(1.0, Double(samples[i])))
            int16Samples[i] = Int16(clamped * Double(Int16.max))
        }
        return Data(bytes: &int16Samples, count: int16Samples.count * MemoryLayout<Int16>.stride)
    }
}

enum RemoteASRError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case serverError(String)
    case cancelled
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:   return "远程服务未配置"
        case .invalidURL:     return "服务地址无效"
        case .serverError(let msg): return "服务端错误：\(msg)"
        case .cancelled:      return "已取消"
        case .invalidResponse: return "服务端响应异常"
        }
    }
}
