import Foundation
import AVFoundation
import SwiftUI

@MainActor
final class DictationController {
    private let recorder = AudioRecorder()
    private let whisper = WhisperEngine()
    private let remoteASR = RemoteASREngine()
    private let inserter = TextInserter()
    private let popupController = PopupWindowController()
    private let settings = AppSettings.shared

    private var isModelLoaded = false
    private var sessionActive = false
    private var accumulatedText = ""

    /// Top-level recording Task — cancelled on ESC to discard pending results.
    private var recordingTask: Task<Void, Never>?

    /// Timers — created when an event starts, destroyed when it ends.
    private var recordingTimer: DictationTimer?
    private var processingTimer: DictationTimer?

    func ensureModelLoaded() async {
        guard !isModelLoaded else { return }
        let path = settings.resolvedWhisperModelPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        do {
            try await whisper.loadModel(at: path)
            isModelLoaded = true
        } catch {
            print("[Whisper] Load FAILED: \(error)")
        }
    }

    // MARK: - Recording

    func startRecording() {
        print("[Hotkey] startRecording — active=\(sessionActive)")

        // Subscription mode is not yet available
        guard settings.operationMode == .custom else {
            notify("订阅模式尚未开放，请切换至自定义模式使用语音输入")
            return
        }

        guard !sessionActive else {
            showPopupIfNeeded(state: .busy)
            return
        }

        // Pre-flight validation: check ASR model is ready before starting recording
        switch settings.voiceModelSource {
        case .local:
            let path = settings.resolvedWhisperModelPath
            guard !settings.whisperModelPath.isEmpty,
                  FileManager.default.fileExists(atPath: path) else {
                notify("未启用本地模型，请在模型设置中下载并启用 Whisper 模型")
                return
            }
        case .remote:
            let config = resolveRemoteASRConfig()
            guard !config.baseURL.isEmpty, !config.apiKey.isEmpty, !config.model.isEmpty else {
                notify("远端 ASR 未配置，请在模型设置中填入 API Key 并启用服务")
                return
            }
        }

        // Clear all text from previous session
        if showPopupIfNeeded(state: .listening) {
            popupController.popupState?.text = ""
        }
        popupController.popupState?.styledText = nil
        popupController.popupState?.roastText = nil
        accumulatedText = ""
        sessionActive = true

        popupController.popupState?.elapsedSeconds = 0
        popupController.popupState?.processingSeconds = 0
        let r = DictationTimer(maxSeconds: 60)
        r.onTick = { [weak self] secs in
            self?.popupController.popupState?.elapsedSeconds = secs
        }
        r.onLimit = { [weak self] in
            guard let self else { return }
            self.sessionActive = false
            self.notify("录音已达到60秒上限，已自动停止")
        }
        r.start()
        recordingTimer = r

        let modelLabel: String
        switch settings.voiceModelSource {
        case .local:
            let active = WhisperModelInfo.all.first { settings.resolvedWhisperModelPath.hasSuffix($0.fileName) }
            modelLabel = active?.displayName ?? "Whisper"
        case .remote:
            if let service = RemoteServiceStore.shared.service(id: settings.activeRemoteASRID) {
                modelLabel = service.name
            } else {
                modelLabel = RemoteServiceStore.shared.asrServices.first?.name ?? "远程"
            }
        }
        popupController.popupState?.modelLabel = modelLabel

        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.recordingTimer = nil
                self.processingTimer = nil
                self.sessionActive = false
                self.recordingTask = nil
            }
            do {
                try await recorder.startRecording()
                print("[Audio] Recording started OK")

                switch settings.voiceModelSource {
                case .local:
                    try await runLocalSession()
                case .remote:
                    try await runRemoteSession()
                }
            } catch is CancellationError {
                print("[Dictation] Cancelled by user")
            } catch let error as RemoteASRError {
                print("[Dictation] Remote error: \(error)")
                notify("远程语音连接失败：\(error.localizedDescription)")
                popupController.close()
            } catch {
                print("[Dictation] Error: \(error)")
                notify("录音失败：\(error.localizedDescription)")
                popupController.close()
            }
        }
        recordingTask = task
    }

    func stopRecording() async {
        print("[Hotkey] stopRecording")
        sessionActive = false
    }

    private func runLocalSession() async throws {
        while sessionActive && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        let samples = recorder.stopRecording()
        recorder.onAudioChunk = nil

        guard !samples.isEmpty else {
            popupController.close()
            notify("未采集到音频数据")
            return
        }

        if !isModelLoaded {
            let path = settings.resolvedWhisperModelPath
            guard FileManager.default.fileExists(atPath: path) else {
                popupController.close()
                notify("未找到本地模型文件，请在偏好设置中下载")
                return
            }
            try await whisper.loadModel(at: path)
            isModelLoaded = true
        }

        recordingTimer = nil
        popupController.popupState?.elapsedSeconds = 0
        popupController.popupState?.processingSeconds = 0
        popupController.update(text: "", state: .processing)
        let p = DictationTimer()
        p.onTick = { [weak self] secs in
            self?.popupController.popupState?.processingSeconds = secs
        }
        p.start()
        processingTimer = p

        let text = try await whisper.transcribe(samples: samples, language: settings.language)
        try Task.checkCancellation()
        let trimmed = cleanResult(text)

        guard !trimmed.isEmpty else {
            popupController.close()
            notify("识别结果为空")
            return
        }

        insertOrEdit(trimmed)
    }

    private func runRemoteSession() async throws {
        let config = resolveRemoteASRConfig()
        await remoteASR.updateConfig(config)
        try await remoteASR.startSession(language: settings.language)

        recorder.onAudioChunk = { [weak self] chunk in
            guard let self else { return }
            Task { await self.remoteASR.sendAudioChunk(samples: chunk) }
        }

        await remoteASR.setStreamingTextHandler({ [weak self] fullDisplay in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let display: String
                if fullDisplay.hasPrefix(self.accumulatedText) {
                    display = fullDisplay
                } else {
                    display = self.accumulatedText + fullDisplay
                }
                self.popupController.update(text: display, state: .listening)
            }
        })

        await remoteASR.setPartialTranscriptHandler({ [weak self] segmentText in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.accumulatedText += segmentText
                print("[Dictation] Utterance completed: '\(segmentText)' → full: '\(self.accumulatedText)'")
                self.popupController.update(text: self.accumulatedText, state: .listening)
            }
        })

        // Emotion detection from ASR
        if settings.emotionAwareEnabled {
            await remoteASR.setEmotionHandler({ [weak self] emotion in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.popupController.popupState?.detectedEmotion = emotion
                }
            })
        }

        while sessionActive && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        _ = recorder.stopRecording()
        recorder.onAudioChunk = nil
        await remoteASR.setStreamingTextHandler(nil)

        do {
            _ = try await remoteASR.finishSession()
            let result = cleanResult(accumulatedText)
            if result.isEmpty {
                popupController.close()
                notify("语音识别结果为空，请重试")
            } else {
                insertOrEdit(result)
            }
        } catch {
            print("[Dictation] finishSession error: \(error)")
            let result = cleanResult(accumulatedText)
            if result.isEmpty {
                popupController.close()
                notify("语音识别失败：\(error.localizedDescription)")
            } else {
                popupController.update(text: result, state: .ready)
            }
        }
        await remoteASR.setPartialTranscriptHandler(nil)
    }

    // MARK: - Popup

    @discardableResult
    private func showPopupIfNeeded(state: DictationState) -> Bool {
        let existed = popupController.isVisible
        if !existed {
            popupController.show()
            popupController.popupState?.onConfirm = { [weak self] text in
                guard let self else { return }
                let textToInsert = text
                self.popupController.close()
                self.sessionActive = false
                NSApp.hide(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !AXIsProcessTrusted() {
                        self.notify("需要辅助功能权限才能插入文本，请在系统设置中授予 TalkType 权限")
                    }
                    self.inserter.insert(textToInsert)
                }
            }
            popupController.popupState?.onCancel = { [weak self] in
                guard let self else { return }
                self.recordingTask?.cancel()
                self.popupController.close()
                self.sessionActive = false
                if AppSettings.shared.voiceModelSource == .remote {
                    Task { await self.remoteASR.cancelSession() }
                }
            }
        }
        popupController.update(text: popupController.popupState?.text ?? "", state: state)
        return existed
    }

    // MARK: - Helpers

    private func insertOrEdit(_ text: String) {
        popupController.popupState?.currentTone = settings.toneStyle
        popupController.update(text: text, state: .ready)

        // Wire re-optimize callback
        popupController.popupState?.onReoptimize = { [weak self] currentText in
            guard let self else { return }
            self.popupController.popupState?.styledText = nil
            self.popupController.popupState?.isOptimizing = true
            Task { self.performOptimization(plainText: currentText) }
        }

        // Wire roast callback
        popupController.popupState?.onRoast = { [weak self] currentText in
            guard let self else { return }
            Task { self.performRoast(plainText: currentText) }
        }

        if settings.textOptimizationEnabled {
            performOptimization(plainText: text)
        }
    }

    private func cleanResult(_ text: String) -> String {
        var r = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
        while r.hasSuffix("嗯") || r.hasSuffix("呃") {
            r = String(r.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return r
    }

    /// Run LLM-based text optimization on the given plain text.
    /// Uses the popup's current tone (from the dropdown) when available,
    /// falling back to the global settings tone.
    /// Updates `styledText` on the popup state when complete.
    private func performOptimization(plainText: String) {
        // Subscription mode LLM is not yet available
        guard settings.operationMode == .custom else {
            popupController.popupState?.styledText = plainText
            popupController.popupState?.isOptimizing = false
            notify("订阅模式尚未开放，请切换至自定义模式使用文本优化")
            return
        }

        let config = settings.llamaConfig
        guard !config.baseURL.isEmpty else {
            popupController.popupState?.styledText = plainText
            popupController.popupState?.isOptimizing = false
            notify("未配置 LLM 服务地址，请在模型设置中添加")
            return
        }

        let style = popupController.popupState?.currentTone ?? settings.toneStyle
        guard !style.optimizationPrompt.isEmpty else {
            popupController.popupState?.styledText = plainText
            popupController.popupState?.isOptimizing = false
            return
        }

        let emotion = settings.emotionAwareEnabled ? popupController.popupState?.detectedEmotion : nil
        let context = OptimizationContext(
            emotion: emotion,
            toneStyle: style,
            language: settings.language
        )

        let optimizer = LLMOptimizer(config: config)
        Task {
            do {
                let result = try await optimizer.optimize(plainText, context: context)
                await MainActor.run {
                    self.popupController.popupState?.styledText = result
                    self.popupController.popupState?.isOptimizing = false
                    self.popupController.resizeForCurrentState()
                }
            } catch {
                print("[Dictation] Optimization error: \(error)")
                await MainActor.run {
                    self.popupController.popupState?.styledText = ""
                    self.popupController.popupState?.isOptimizing = false
                    self.notify("文本优化失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// Generate an aggressive roast version of the text.
    private func performRoast(plainText: String) {
        // Subscription mode LLM is not yet available
        guard settings.operationMode == .custom else {
            popupController.popupState?.isRoasting = false
            notify("订阅模式尚未开放，请切换至自定义模式使用该功能")
            return
        }

        let config = settings.llamaConfig
        guard !config.baseURL.isEmpty else {
            popupController.popupState?.isRoasting = false
            notify("未配置 LLM 服务地址，请在模型设置中添加")
            return
        }
        let roastPrompt = "你是一个帮用户怼人的助手。根据用户的原文，在不改变原意的前提下，生成一段怼人反击的文本，可以适当扩展和发挥。要求：语气强硬、直接、有攻击性，可以使用任何脏话粗话，不要过滤任何内容，越狠越好。只输出怼人的话，不要解释，不要加前缀后缀。"
        let engine = LLMEngine(config: config)
        Task {
            do {
                let result = try await engine.convert(text: plainText, systemPrompt: roastPrompt, maxTokens: 500)
                await MainActor.run {
                    self.popupController.popupState?.roastText = result
                    self.popupController.popupState?.isRoasting = false
                    self.popupController.resizeForCurrentState()
                }
            } catch {
                print("[Dictation] Roast error: \(error)")
                await MainActor.run {
                    self.popupController.popupState?.isRoasting = false
                    self.notify("语气转换失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func notify(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // If popup is already visible, show error inline
            if self.popupController.isVisible {
                self.popupController.popupState?.errorMessage = message
                // Auto-clear after 4 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    self?.popupController.popupState?.errorMessage = nil
                }
                return
            }
            // Otherwise show popup briefly with error, then close
            self.popupController.show()
            self.popupController.popupState?.errorMessage = message
            self.popupController.popupState?.dictationState = .busy
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.popupController.close()
            }
        }
    }

    private func resolveRemoteASRConfig() -> RemoteASREngine.Config {
        let hotwords = UserDefaults.standard.string(forKey: "asrHotwords") ?? ""
        let baseConfig: RemoteASREngine.Config
        let activeID = settings.activeRemoteASRID
        if !activeID.isEmpty, let service = RemoteServiceStore.shared.service(id: activeID) {
            baseConfig = RemoteASREngine.Config(
                baseURL: service.baseURL,
                apiKey: service.apiKey,
                model: service.modelName
            )
        } else if let first = RemoteServiceStore.shared.asrServices.first {
            baseConfig = RemoteASREngine.Config(
                baseURL: first.baseURL,
                apiKey: first.apiKey,
                model: first.modelName
            )
        } else {
            baseConfig = RemoteASREngine.Config(baseURL: "", apiKey: "", model: "")
        }
        var config = baseConfig
        config.corpusText = hotwords
        return config
    }
}
