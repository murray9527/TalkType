import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - Advanced features

    @AppStorage("advancedEnabled") var advancedEnabled: Bool = false

    // MARK: - Voice model source

    @AppStorage("voiceModelSourceRaw") var voiceModelSourceRaw: String = VoiceModelSource.remote.rawValue
    var voiceModelSource: VoiceModelSource {
        get { VoiceModelSource(rawValue: voiceModelSourceRaw) ?? .remote }
        set { voiceModelSourceRaw = newValue.rawValue }
    }

    // MARK: - Refinement model source

    @AppStorage("refinementModelSourceRaw") var refinementModelSourceRaw: String = RefinementModelSource.remote.rawValue
    var refinementModelSource: RefinementModelSource {
        get { RefinementModelSource(rawValue: refinementModelSourceRaw) ?? .remote }
        set { refinementModelSourceRaw = newValue.rawValue }
    }

    // MARK: - Active remote service IDs

    @AppStorage("activeRemoteASRID") var activeRemoteASRID: String = ""
    @AppStorage("activeRemoteLLMID") var activeRemoteLLMID: String = ""

    // MARK: - Local Whisper

    @AppStorage("whisperModelPath") var whisperModelPath: String = ""

    var resolvedWhisperModelPath: String {
        if !whisperModelPath.isEmpty { return whisperModelPath }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("TalkType/models/ggml-small.bin").path
    }

    // MARK: - Tone & language

    @AppStorage("toneStyle") var toneStyleRaw: String = ToneStyle.none.rawValue
    @AppStorage("language") var language: String = "zh"

    var toneStyle: ToneStyle {
        get { ToneStyle(rawValue: toneStyleRaw) ?? .none }
        set { toneStyleRaw = newValue.rawValue }
    }

    // MARK: - Recording

    @AppStorage("maxRecordingDuration") var maxRecordingDuration: Double = 60

    // MARK: - Text optimization

    /// Master toggle for LLM-based text optimization after ASR.
    @AppStorage("textOptimizationEnabled") var textOptimizationEnabled: Bool = false

    /// When enabled, ASR emotion data is passed to the LLM optimization prompt.
    @AppStorage("emotionAwareEnabled") var emotionAwareEnabled: Bool = true

    // MARK: - Hotkey

    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode: Int = 0x3F  // kVK_Function
    @AppStorage("hotkeyModifiers") var hotkeyModifiers: Int = 0

    // MARK: - Edit before insert

    /// When enabled, shows an editable popup after recognition (phase 3).
    /// When disabled, inserts text directly after recognition.
    @AppStorage("enableReedit") var enableReedit: Bool = false

    // MARK: - Legacy LLM fields (kept for migration)

    @AppStorage("llmBaseURL") var llmBaseURL: String = "http://127.0.0.1:11434/v1"
    @AppStorage("llmApiKey") var llmApiKey: String = ""
    @AppStorage("llmModel") var llmModel: String = "qwen3:0.6b"

    // MARK: - Migration

    private let migrateKey = "hasMigratedToRepositioning"

    private func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrateKey) else { return }

        // If user had a non-"不调整" tone style, they were using advanced features
        let hadTone = toneStyle != .none
        if hadTone {
            advancedEnabled = true
        }

        // Migrate old LLM config into RemoteServiceStore as a user entry
        let hasLLMConfig = !llmBaseURL.isEmpty || !llmModel.isEmpty
        if hasLLMConfig {
            advancedEnabled = true
            let service = RemoteService(
                id: UUID().uuidString,
                name: "自定义 LLM",
                type: .llm,
                baseURL: llmBaseURL.isEmpty ? "http://127.0.0.1:8080" : llmBaseURL,
                apiKey: llmApiKey,
                modelName: llmModel,
                isPreset: false
            )
            RemoteServiceStore.shared.addService(service)
            activeRemoteLLMID = service.id
        }

        // Default ASR source is remote (Aliyun preset)
        voiceModelSourceRaw = VoiceModelSource.remote.rawValue
        // Auto-select Aliyun Qwen-ASR preset if no active remote ASR is set
        if activeRemoteASRID.isEmpty {
            activeRemoteASRID = "preset-alibaba-asr"
        }

        UserDefaults.standard.set(true, forKey: migrateKey)
    }

    // MARK: - Init

    private init() {
        migrateIfNeeded()
    }

    // MARK: - Convenience

    /// Tone conversion is active when a non-none style is selected.
    var isToneConversionEnabled: Bool { toneStyle != .none }

    /// Resolves the active LLM config from RemoteServiceStore, or falls back to legacy fields.
    var llamaConfig: LLMEngine.Config {
        let activeID = activeRemoteLLMID
        if !activeID.isEmpty, let service = RemoteServiceStore.shared.service(id: activeID) {
            return LLMEngine.Config.from(service: service)
        }
        return LLMEngine.Config(
            baseURL: llmBaseURL.isEmpty ? "http://127.0.0.1:8080" : llmBaseURL,
            apiKey: llmApiKey,
            model: llmModel,
            maxTokens: 300,
            temperature: 0.3
        )
    }
}

// MARK: - Enums

enum VoiceModelSource: String, CaseIterable, Identifiable {
    case local, remote, subscription

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "本地模型"
        case .remote: return "自定义接口"
        case .subscription: return "官方订阅"
        }
    }
}

enum RefinementModelSource: String, CaseIterable, Identifiable {
    case local, remote, subscription

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "本地模型"
        case .remote: return "自定义接口"
        case .subscription: return "官方订阅"
        }
    }
}
