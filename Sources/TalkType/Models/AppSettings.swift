import Foundation
import SwiftUI

// App-wide user settings, persisted via UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // ASR model
    @AppStorage("whisperModelPath") var whisperModelPath: String = ""

    // LLM service
    @AppStorage("llmBaseURL") var llmBaseURL: String = "http://127.0.0.1:8080"
    @AppStorage("llmApiKey") var llmApiKey: String = ""
    @AppStorage("llmModel") var llmModel: String = ""

    // Behaviour
    @AppStorage("toneStyle") var toneStyleRaw: String = ToneStyle.none.rawValue
    @AppStorage("language") var language: String = "zh"

    var toneStyle: ToneStyle {
        get { ToneStyle(rawValue: toneStyleRaw) ?? .none }
        set { toneStyleRaw = newValue.rawValue }
    }

    var isToneConversionEnabled: Bool { toneStyle != .none }

    var resolvedWhisperModelPath: String {
        if !whisperModelPath.isEmpty { return whisperModelPath }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("TalkType/models/ggml-small.bin").path
    }

    var llamaConfig: LlamaEngine.Config {
        LlamaEngine.Config(
            baseURL: llmBaseURL.isEmpty ? "http://127.0.0.1:8080" : llmBaseURL,
            apiKey: llmApiKey,
            model: llmModel,
            maxTokens: 300,
            temperature: 0.3
        )
    }
}
