import Foundation
import whisper

/// Thread-safe flag for signalling cancellation across task boundaries.
final class CancelFlag: @unchecked Sendable {
    var isSet = false
}

actor WhisperEngine {
    nonisolated(unsafe) private var context: OpaquePointer?
    private var isTranscribing = false

    enum WhisperError: Error {
        case modelNotLoaded
        case transcriptionFailed
        case busy
    }

    func loadModel(at path: String) throws {
        let params = whisper_context_default_params()
        guard let ctx = whisper_init_from_file_with_params(path, params) else {
            throw WhisperError.modelNotLoaded
        }
        if let old = context { whisper_free(old) }
        context = ctx
    }

    func checkBusy() throws {
        guard !isTranscribing else { throw WhisperError.busy }
    }

    func transcribe(samples: [Float], language: String = "zh") async throws -> String {
        guard let ctx = context else { throw WhisperError.modelNotLoaded }
        guard !isTranscribing else {
            print("[Whisper] Busy — dropping overlapping transcription request")
            throw WhisperError.busy
        }
        isTranscribing = true
        defer { isTranscribing = false }

        try Task.checkCancellation()

        let nsLang = language as NSString
        nonisolated(unsafe) let capturedCtx = ctx
        nonisolated(unsafe) var capturedParams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        capturedParams.language = nsLang.utf8String
        capturedParams.translate = false
        capturedParams.no_context = true
        capturedParams.single_segment = false
        capturedParams.print_progress = false
        capturedParams.print_realtime = false
        capturedParams.print_timestamps = false

        let flag = CancelFlag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task.detached {
                    let rc = samples.withUnsafeBufferPointer { ptr in
                        whisper_full(capturedCtx, capturedParams, ptr.baseAddress, Int32(ptr.count))
                    }

                    if flag.isSet {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    guard rc == 0 else {
                        continuation.resume(throwing: WhisperError.transcriptionFailed)
                        return
                    }

                    let segmentCount = whisper_full_n_segments(capturedCtx)
                    var text = ""
                    for i in 0..<segmentCount {
                        if let t = whisper_full_get_segment_text(capturedCtx, i) {
                            text += String(cString: t)
                        }
                    }

                    if flag.isSet {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(returning: text.trimmingCharacters(in: .whitespaces))
                    }
                }
            }
        } onCancel: {
            flag.isSet = true
        }
    }

    func unload() {
        if let ctx = context { whisper_free(ctx) }
        context = nil
    }

    deinit {
        if let ctx = context { whisper_free(ctx) }
    }
}
