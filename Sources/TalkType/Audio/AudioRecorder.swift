import AVFoundation

// Captures microphone audio and accumulates PCM samples for Whisper.
// Whisper expects 16kHz mono float32 audio.
final class AudioRecorder: NSObject {
    private var engine = AVAudioEngine()
    private(set) var samples: [Float] = []
    private let targetSampleRate: Double = 16000

    var isRecording = false

    func startRecording() throws {
        samples = []
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

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

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * targetSampleRate / inputFormat.sampleRate)
            guard let converted = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: frameCount) else { return }
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if let channelData = converted.floatChannelData?[0] {
                let count = Int(converted.frameLength)
                self.samples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: count))
            }
        }

        try engine.start()
        isRecording = true
    }

    func stopRecording() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return samples
    }
}

enum AudioError: Error {
    case formatCreationFailed
    case converterCreationFailed
}
