@preconcurrency import AVFoundation

// Thread-safe sample accumulator shared between the audio thread (tap callback)
// and MainActor (stopRecording reads, then clears).
private final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var _samples: [Float] = []

    func append(_ newSamples: UnsafeBufferPointer<Float>) {
        lock.lock()
        _samples.append(contentsOf: newSamples)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        _samples.removeAll()
        lock.unlock()
    }

    func takeAll() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let result = _samples
        _samples.removeAll()
        return result
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _samples.isEmpty
    }
}

// The tap callback fires on a background audio thread and cannot access @MainActor self,
// so we store the callback behind a lock and pass a captured reference into the closure.
private final class ChunkCallbackHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _callback: (@Sendable ([Float]) -> Void)?

    var callback: (@Sendable ([Float]) -> Void)? {
        get { lock.withLock { _callback } }
        set { lock.withLock { _callback = newValue } }
    }
}

// Wraps AVFoundation objects needed by the audio tap closure so they can be
// safely captured across the @MainActor → audio-thread isolation boundary.
// AVAudioConverter and AVAudioFormat are internally thread-safe but not
// marked Sendable, so Swift 6's complete concurrency checking would assert.
private final class TapConversionContext: @unchecked Sendable {
    let converter: AVAudioConverter
    let whisperFormat: AVAudioFormat
    let sourceFormat: AVAudioFormat
    init(converter: AVAudioConverter, whisperFormat: AVAudioFormat, sourceFormat: AVAudioFormat) {
        self.converter = converter
        self.whisperFormat = whisperFormat
        self.sourceFormat = sourceFormat
    }
}

@MainActor
final class AudioRecorder: NSObject {
    private var engine: AVAudioEngine?
    private let sampleBuffer = SampleBuffer()
    private let chunkCallback = ChunkCallbackHolder()
    private let targetSampleRate: Double = 16000
    private var diagnosticTimerTask: Task<Void, Never>?

    var isRecording = false

    /// Closure invoked for each converted audio chunk during recording.
    /// Called on the audio processing thread — the closure itself must be thread-safe.
    /// Typically used to stream audio to a remote ASR service.
    var onAudioChunk: (@Sendable ([Float]) -> Void)? {
        get { chunkCallback.callback }
        set { chunkCallback.callback = newValue }
    }

    var samples: [Float] { sampleBuffer.takeAll() }

    func startRecording() async throws {
        guard await checkMicrophonePermission() else {
            print("[Audio] ERROR: Microphone permission denied — grant access in System Settings → Privacy & Security → Microphone")
            throw AudioError.permissionDenied
        }

        sampleBuffer.reset()
        // Always create a fresh engine — AVAudioEngine cannot be reliably restarted
        let freshEngine = AVAudioEngine()
        engine = freshEngine
        let input = freshEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            print("[Audio] ERROR: Input sample rate is 0 — no microphone detected or default input device is invalid")
            throw AudioError.noInputDevice
        }

        // Whisper needs 16kHz mono float32
        guard let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                sampleRate: targetSampleRate,
                                                channels: 1,
                                                interleaved: false) else {
            throw AudioError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: whisperFormat) else {
            throw AudioError.converterCreationFailed
        }

        print("[Audio] Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        // Capture references for use on the audio callback thread.
        // The tap closure must never access self (which is @MainActor), otherwise
        // Swift 6's executor assertion crashes with dispatch_assert_queue_fail.
        // We also wrap non-Sendable AVFoundation objects in @unchecked Sendable
        // containers — they are thread-safe ObjC classes but Swift 6's complete
        // concurrency checking would still flag the isolation boundary crossing.
        //
        // CRITICAL: installTap is called via a nonisolated static helper so the
        // closure is created OUTSIDE @MainActor context. If created directly here,
        // the closure inherits MainActor isolation and Swift 6 crashes with
        // swift_task_isCurrentExecutorWithFlagsImpl when AVFAudio invokes it
        // on the audio I/O thread.
        let buffer = self.sampleBuffer
        let chunkCB = self.chunkCallback
        let tapCtx = TapConversionContext(converter: converter, whisperFormat: whisperFormat, sourceFormat: inputFormat)
        let sr = targetSampleRate
        Self.installAudioTap(on: freshEngine,
                             inputFormat: inputFormat,
                             buffer: buffer,
                             chunkCB: chunkCB,
                             tapCtx: tapCtx,
                             sr: sr)

        try freshEngine.start()
        isRecording = true
        startDiagnosticTimer()
    }

    func stopRecording() -> [Float] {
        stopDiagnosticTimer()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRecording = false
        return sampleBuffer.takeAll()
    }

    // MARK: - Tap installation (nonisolated to avoid @MainActor taint)

    nonisolated private static func installAudioTap(on engine: AVAudioEngine,
                                                     inputFormat: AVAudioFormat,
                                                     buffer: SampleBuffer,
                                                     chunkCB: ChunkCallbackHolder,
                                                     tapCtx: TapConversionContext,
                                                     sr: Double) {
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { pcmBuffer, _ in
            let frameCount = AVAudioFrameCount(Double(pcmBuffer.frameLength) * sr / tapCtx.sourceFormat.sampleRate)
            guard let converted = AVAudioPCMBuffer(pcmFormat: tapCtx.whisperFormat, frameCapacity: frameCount) else { return }
            var error: NSError?
            nonisolated(unsafe) var inputConsumed = false
            tapCtx.converter.convert(to: converted, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return pcmBuffer
            }
            if let error {
                print("[AudioRecorder] Conversion error: \(error)")
                return
            }
            if let channelData = converted.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(converted.frameLength)))
                samples.withUnsafeBufferPointer { buffer.append($0) }
                chunkCB.callback?(samples)
            }
        }
    }

    // MARK: - Permission

    private func checkMicrophonePermission() async -> Bool {
        // AVCaptureDevice authorization (TCC camera/mic subsystem)
        let captureAuthorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            captureAuthorized = true
        case .notDetermined:
            captureAuthorized = await withCheckedContinuation { continuation in
                // requestAccess presents a system dialog and must run on the
                // main dispatch queue, not just a @MainActor context.
                requestAccessOnMainQueue(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            print("[Audio] AVCaptureDevice authorization denied")
            return false
        @unknown default:
            return false
        }

        guard captureAuthorized else { return false }

        // AVAudioApplication record permission (CoreAudio subsystem, macOS 14+)
        // AVAudioEngine's tap callback will never fire without this on macOS 14+,
        // even when AVCaptureDevice authorization is granted.
        // Like UNUserNotificationCenter, AVAudioApplication.shared may assert
        // pthread_main_np() on macOS 26+ where @MainActor ≠ dispatch_main.
        if #available(macOS 14, *) {
            let avApp = resolveAVAudioApplication()
            switch avApp.recordPermission {
            case .granted:
                return true
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    requestRecordPermissionOnMainQueue { granted in
                        continuation.resume(returning: granted)
                    }
                }
            case .denied:
                print("[Audio] AVAudioApplication record permission denied")
                return false
            @unknown default:
                return false
            }
        }

        return true
    }

    /// Accesses AVAudioApplication.shared on the main dispatch queue when needed,
    /// avoiding the pthread_main_np() assertion that can fire on macOS 26+
    /// where @MainActor may use a cooperative thread pool.
    @available(macOS 14, *)
    private func resolveAVAudioApplication() -> AVAudioApplication {
        if Thread.isMainThread {
            return AVAudioApplication.shared
        }
        return DispatchQueue.main.sync { AVAudioApplication.shared }
    }

    /// Calls AVCaptureDevice.requestAccess on the main dispatch queue.
    private func requestAccessOnMainQueue(for mediaType: AVMediaType,
                                           completion: @escaping @Sendable (Bool) -> Void) {
        if Thread.isMainThread {
            AVCaptureDevice.requestAccess(for: mediaType, completionHandler: completion)
        } else {
            DispatchQueue.main.async {
                AVCaptureDevice.requestAccess(for: mediaType, completionHandler: completion)
            }
        }
    }

    /// Calls AVAudioApplication.requestRecordPermission on the main dispatch queue.
    @available(macOS 14, *)
    private func requestRecordPermissionOnMainQueue(completion: @escaping @Sendable (Bool) -> Void) {
        if Thread.isMainThread {
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        } else {
            DispatchQueue.main.async {
                AVAudioApplication.requestRecordPermission(completionHandler: completion)
            }
        }
    }

    // MARK: - Diagnostic timer

    // Uses Task.sleep instead of DispatchSource timer to avoid Swift 6
    // executor isolation crashes. A DispatchSource on a .global() queue
    // that captures [weak self] (AudioRecorder is @MainActor) triggers
    // swift_task_isCurrentExecutorWithFlagsImpl in the event handler.
    private func startDiagnosticTimer() {
        let buffer = self.sampleBuffer
        diagnosticTimerTask = Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            if buffer.isEmpty {
                print("[Audio] WARNING: 1 second elapsed but tap callback has not fired — likely microphone permission or no input device")
            }
            await MainActor.run {
                self?.stopDiagnosticTimer()
            }
        }
    }

    private func stopDiagnosticTimer() {
        diagnosticTimerTask?.cancel()
        diagnosticTimerTask = nil
    }
}

enum AudioError: Error {
    case permissionDenied
    case noInputDevice
    case formatCreationFailed
    case converterCreationFailed
}
