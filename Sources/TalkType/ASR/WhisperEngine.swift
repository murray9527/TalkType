import Foundation
import whisper

// Wraps whisper.cpp context and performs transcription on 16kHz float32 PCM samples.
actor WhisperEngine {
    private var context: OpaquePointer?

    enum WhisperError: Error {
        case modelNotLoaded
        case transcriptionFailed
    }

    func loadModel(at path: String) throws {
        let params = whisper_context_default_params()
        guard let ctx = whisper_init_from_file_with_params(path, params) else {
            throw WhisperError.modelNotLoaded
        }
        if let old = context { whisper_free(old) }
        context = ctx
    }

    func transcribe(samples: [Float], language: String = "zh") throws -> String {
        guard let ctx = context else { throw WhisperError.modelNotLoaded }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.language = (language as NSString).utf8String
        params.translate = false
        params.no_context = true
        params.single_segment = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false

        let result = samples.withUnsafeBufferPointer { ptr in
            whisper_full(ctx, params, ptr.baseAddress, Int32(ptr.count))
        }
        guard result == 0 else { throw WhisperError.transcriptionFailed }

        let segmentCount = whisper_full_n_segments(ctx)
        var text = ""
        for i in 0..<segmentCount {
            if let t = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: t)
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    func unload() {
        if let ctx = context { whisper_free(ctx) }
        context = nil
    }
}
