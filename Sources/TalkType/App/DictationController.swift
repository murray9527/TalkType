import Foundation
import AVFoundation
import SwiftUI

// Orchestrates the full dictation pipeline:
// Record → Transcribe → Basic correction → (optional) Tone conversion → Insert
@MainActor
final class DictationController {
    private let recorder = AudioRecorder()
    private let whisper = WhisperEngine()
    private let postProcessor = TextPostProcessor()
    private let inserter = TextInserter()
    private let popupController = PopupWindowController()
    private let settings = AppSettings.shared

    private var styledText: String? = nil

    func startRecording() {
        guard !recorder.isRecording else { return }
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

    private func transcribeAndProcess(samples: [Float]) async {
        // Step 1: ASR
        guard let rawText = try? await whisper.transcribe(
            samples: samples,
            language: settings.language
        ), !rawText.isEmpty else { return }

        // Step 2: Basic correction (always)
        let basicText = postProcessor.process(rawText)

        // Step 3: If tone conversion disabled → insert immediately, done
        guard settings.isToneConversionEnabled else {
            inserter.insert(basicText)
            return
        }

        // Step 4: Show popup with basic text; kick off LLM async
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

        // LLM tone conversion runs concurrently
        Task {
            let styled = await convertTone(basicText)
            styledText = styled
        }
    }

    private func convertTone(_ text: String) async -> String {
        // Placeholder — will call llama.cpp engine in Week 5-6
        // For now returns text unchanged so the pipeline is testable end-to-end
        return text
    }
}
