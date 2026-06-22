import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - Operation mode

    @Published var operationModeRaw: String = OperationMode.custom.rawValue {
        didSet { UserDefaults.standard.set(operationModeRaw, forKey: "operationMode") }
    }
    var operationMode: OperationMode {
        get { OperationMode(rawValue: operationModeRaw) ?? .custom }
        set { operationModeRaw = newValue.rawValue }
    }

    // MARK: - Advanced features

    @Published var advancedEnabled: Bool = false {
        didSet { UserDefaults.standard.set(advancedEnabled, forKey: "advancedEnabled") }
    }

    // MARK: - Voice model source

    @Published var voiceModelSourceRaw: String = VoiceModelSource.remote.rawValue {
        didSet { UserDefaults.standard.set(voiceModelSourceRaw, forKey: "voiceModelSourceRaw") }
    }
    var voiceModelSource: VoiceModelSource {
        get { VoiceModelSource(rawValue: voiceModelSourceRaw) ?? .remote }
        set { voiceModelSourceRaw = newValue.rawValue }
    }

    // MARK: - Refinement model source

    @Published var refinementModelSourceRaw: String = RefinementModelSource.remote.rawValue {
        didSet { UserDefaults.standard.set(refinementModelSourceRaw, forKey: "refinementModelSourceRaw") }
    }
    var refinementModelSource: RefinementModelSource {
        get { RefinementModelSource(rawValue: refinementModelSourceRaw) ?? .remote }
        set { refinementModelSourceRaw = newValue.rawValue }
    }

    // MARK: - Active remote service IDs

    @Published var activeRemoteASRID: String = "" {
        didSet { UserDefaults.standard.set(activeRemoteASRID, forKey: "activeRemoteASRID") }
    }
    @Published var activeRemoteLLMID: String = "" {
        didSet { UserDefaults.standard.set(activeRemoteLLMID, forKey: "activeRemoteLLMID") }
    }

    // MARK: - Local Whisper

    @Published var whisperModelPath: String = "" {
        didSet { UserDefaults.standard.set(whisperModelPath, forKey: "whisperModelPath") }
    }

    var resolvedWhisperModelPath: String {
        if !whisperModelPath.isEmpty { return whisperModelPath }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("TalkType/models/ggml-small.bin").path
    }

    // MARK: - Tone & language

    @Published var toneStyleRaw: String = ToneStyle.none.rawValue {
        didSet { UserDefaults.standard.set(toneStyleRaw, forKey: "toneStyle") }
    }
    @Published var language: String = "zh" {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }

    var toneStyle: ToneStyle {
        get { ToneStyle(rawValue: toneStyleRaw) ?? .none }
        set { toneStyleRaw = newValue.rawValue }
    }

    // MARK: - Recording

    @Published var maxRecordingDuration: Double = 60 {
        didSet { UserDefaults.standard.set(maxRecordingDuration, forKey: "maxRecordingDuration") }
    }

    // MARK: - Text optimization

    /// Master toggle for LLM-based text optimization after ASR.
    @Published var textOptimizationEnabled: Bool = false {
        didSet { UserDefaults.standard.set(textOptimizationEnabled, forKey: "textOptimizationEnabled") }
    }

    /// When enabled, ASR emotion data is passed to the LLM optimization prompt.
    @Published var emotionAwareEnabled: Bool = true {
        didSet { UserDefaults.standard.set(emotionAwareEnabled, forKey: "emotionAwareEnabled") }
    }

    // MARK: - Hotkey

    @Published var hotkeyKeyCode: Int = 49 {  // kVK_Space
        didSet { UserDefaults.standard.set(hotkeyKeyCode, forKey: "hotkeyKeyCode") }
    }
    @Published var hotkeyModifiers: Int = 2048 {  // optionKey
        didSet { UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers") }
    }

    // MARK: - Edit before insert

    /// When enabled, shows an editable popup after recognition (phase 3).
    /// When disabled, inserts text directly after recognition.
    @Published var enableReedit: Bool = false {
        didSet { UserDefaults.standard.set(enableReedit, forKey: "enableReedit") }
    }

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

        // Migrate old per-component .subscription to .remote (now a top-level mode)
        if voiceModelSourceRaw == "subscription" { voiceModelSource = .remote }
        if refinementModelSourceRaw == "subscription" { refinementModelSource = .remote }

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
        // Load persisted values
        let defaults = UserDefaults.standard
        operationModeRaw = defaults.string(forKey: "operationMode") ?? OperationMode.custom.rawValue
        advancedEnabled = defaults.bool(forKey: "advancedEnabled")
        voiceModelSourceRaw = defaults.string(forKey: "voiceModelSourceRaw") ?? VoiceModelSource.remote.rawValue
        refinementModelSourceRaw = defaults.string(forKey: "refinementModelSourceRaw") ?? RefinementModelSource.remote.rawValue
        activeRemoteASRID = defaults.string(forKey: "activeRemoteASRID") ?? ""
        activeRemoteLLMID = defaults.string(forKey: "activeRemoteLLMID") ?? ""
        whisperModelPath = defaults.string(forKey: "whisperModelPath") ?? ""
        toneStyleRaw = defaults.string(forKey: "toneStyle") ?? ToneStyle.none.rawValue
        language = defaults.string(forKey: "language") ?? "zh"
        maxRecordingDuration = defaults.double(forKey: "maxRecordingDuration")
        if maxRecordingDuration == 0 { maxRecordingDuration = 60 }
        textOptimizationEnabled = defaults.bool(forKey: "textOptimizationEnabled")
        emotionAwareEnabled = defaults.bool(forKey: "emotionAwareEnabled")
        hotkeyKeyCode = defaults.integer(forKey: "hotkeyKeyCode")
        if hotkeyKeyCode == 0 { hotkeyKeyCode = 0x3F }
        hotkeyModifiers = defaults.integer(forKey: "hotkeyModifiers")
        enableReedit = defaults.bool(forKey: "enableReedit")

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

enum OperationMode: String, CaseIterable, Identifiable {
    case subscription, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .subscription: return "订阅模式"
        case .custom: return "自定义模式"
        }
    }
}

enum VoiceModelSource: String, CaseIterable, Identifiable {
    case local, remote

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "本地模型"
        case .remote: return "远端模型"
        }
    }
}

enum RefinementModelSource: String, CaseIterable, Identifiable {
    case local, remote

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "本地模型"
        case .remote: return "远端模型"
        }
    }
}
