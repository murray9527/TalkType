import Foundation
import AVFoundation
import SwiftUI

// Orchestrates the full dictation pipeline:
// Record → Transcribe → Basic correction → (optional) Tone conversion → Insert
@MainActor
final class DictationController {
    private let recorder = AudioRecorder()
    private let whisper = WhisperEngine()
    private let llama = LlamaEngine()
    private let postProcessor = TextPostProcessor()
    private let inserter = TextInserter()
    private let popupController = PopupWindowController()
    private let settings = AppSettings.shared

    private var styledText: String? = nil
    private var isModelLoaded = false

    init() {
        Task { await loadWhisper() }
    }

    private func loadWhisper() async {
        let path = settings.resolvedWhisperModelPath
        guard FileManager.default.fileExists(atPath: path) else {
            print("[DictationController] Whisper model not found at: \(path)")
            return
        }
        do {
            try await whisper.loadModel(at: path)
            isModelLoaded = true
            print("[DictationController] Whisper loaded: \(URL(fileURLWithPath: path).lastPathComponent)")
        } catch {
            print("[DictationController] Whisper load failed: \(error)")
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard !recorder.isRecording else { return }
        guard isModelLoaded else {
            print("[DictationController] Whisper not loaded yet")
            return
        }
        do {
            try recorder.startRecording()
        } catch {
            print("[DictationController] Recording failed: \(error)")
        }
    }

    func stopRecording() {
        let samples = recorder.stopRecording()
        guard !samples.isEmpty else { return }
        Task { await transcribeAndProcess(samples: samples) }
    }

    // MARK: - Pipeline

    private func transcribeAndProcess(samples: [Float]) async {
        // Step 1: ASR
        guard let rawText = try? await whisper.transcribe(
            samples: samples,
            language: settings.language
        ), !rawText.isEmpty else { return }

        // Step 2: Basic correction (always)
        let basicText = postProcessor.process(rawText)
        print("[Pipeline] basic: \(basicText)")

        // Step 3: No tone conversion → insert immediately
        guard settings.isToneConversionEnabled else {
            inserter.insert(basicText)
            return
        }

        // Step 4: Show popup; LLM conversion runs concurrently
        styledText = nil
        let styledBinding = Binding<String?>(
            get: { [weak self] in self?.styledText },
            set: { [weak self] val in self?.styledText = val }
        )

        popupController.show(
            basicText: basicText,
            styledTextBinding: styledBinding,
            onSelect: { [weak self] text in self?.inserter.insert(text) },
            onDismiss: {}
        )

        Task {
            let styled = await convertTone(basicText)
            print("[Pipeline] styled (\(settings.toneStyle.rawValue)): \(styled)")
            styledText = styled
        }
    }

    private func convertTone(_ text: String) async -> String {
        // Update LLM config from latest settings before each call
        await llama.updateConfig(settings.llamaConfig)
        do {
            return try await llama.convert(
                text: text,
                systemPrompt: settings.toneStyle.systemPrompt
            )
        } catch {
            print("[DictationController] LLM inference failed: \(error) — using basic text")
            return text
        }
    }
}
