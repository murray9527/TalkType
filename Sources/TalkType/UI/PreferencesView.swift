import SwiftUI
import AVFoundation
import ApplicationServices

struct PreferencesView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("一般设置", systemImage: "gearshape") }

            modelTab
                .tabItem { Label("模型设置", systemImage: "waveform") }
        }
        .frame(width: 560, height: 520)
    }

    // MARK: - General Tab

    @ViewBuilder
    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                permissionsSection
                hotkeySection
                hotwordsSection
                optimizationSection
            }
            .padding()
        }
    }

    // MARK: - Model Tab

    @ViewBuilder
    private var modelTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 订阅状态提示（暂未开放）
                subscriptionStatusBar
                customModelContent
            }
            .padding()
        }
    }

    private var subscriptionStatusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .foregroundColor(.orange)
                .font(.system(size: 13))
            Text("订阅模式")
                .font(.subheadline)
            Spacer()
            Text("暂未开放")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
            Text("敬请期待")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Custom Mode Content

    @ViewBuilder
    private var customModelContent: some View {
        asrSection
        llmSection
    }

    // MARK: - ASR Section

    @ViewBuilder
    private var asrSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("语音识别（ASR）", systemImage: "waveform")
                    .font(.headline)

                Picker("识别语言", selection: $settings.language) {
                    Text("中文").tag("zh")
                    Text("英文").tag("en")
                    Text("自动检测").tag("auto")
                }

                Divider()

                Picker("模型来源", selection: $settings.voiceModelSourceRaw) {
                    ForEach(VoiceModelSource.allCases) { source in
                        Text(source.displayName).tag(source.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                switch settings.voiceModelSource {
                case .local:
                    ASRLocalContent()
                case .remote:
                    ASRRemoteContent()
                }
            }
            .padding(8)
        }
    }

    // MARK: - Hotwords Section

    @ViewBuilder
    private var hotwordsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("热词", systemImage: "text.word.spacing")
                    .font(.headline)
                Text("输入需要优先识别的人名、专有名词等，用逗号分隔（部分模型支持）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("如：张三, 机器学习, 人工智能", text: hotwordsBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
            .padding(8)
        }
    }

    // MARK: - Hotkey Section

    @ViewBuilder
    private var hotkeySection: some View {
        GroupBox {
            HStack {
                Label("全局热键", systemImage: "keyboard")
                    .font(.headline)
                Spacer()
                HotkeyRecorderView()
            }
            .padding(8)
        }
    }

    // MARK: - Text Optimization Section

    @ViewBuilder
    private var optimizationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("文本优化", systemImage: "text.quote")
                    .font(.headline)

                Toggle("启用文本优化", isOn: $settings.textOptimizationEnabled)
                    .toggleStyle(.switch)

                Text("开启后，识别完成将展示文本编辑框，并启用 LLM 文本优化。可在编辑框中选择转换风格。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }

    // MARK: - LLM Section

    @ViewBuilder
    private var llmSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("语气转换（LLM）", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.headline)

                LLMServiceList()
            }
            .padding(8)
        }
    }

    // MARK: - Permissions Section

    @ViewBuilder
    private var permissionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("权限", systemImage: "lock.shield")
                    .font(.headline)

                PermissionRow(
                    icon: "mic.fill",
                    title: "麦克风权限",
                    description: "用于语音录制和识别",
                    isGranted: microphonePermissionGranted,
                    onRequest: requestMicrophonePermission
                )

                Divider()

                PermissionRow(
                    icon: "keyboard",
                    title: "辅助功能权限",
                    description: "用于模拟键盘输入文字",
                    isGranted: accessibilityPermissionGranted,
                    onRequest: requestAccessibilityPermission
                )
            }
            .padding(8)
        }
    }

    private var microphonePermissionGranted: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return status == .authorized
    }

    private var accessibilityPermissionGranted: Bool {
        AXIsProcessTrusted()
    }

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        if #available(macOS 14, *) {
            AVAudioApplication.requestRecordPermission { _ in }
        }
    }

    private func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Hotword text saved to corpusText on ASR Config.
    private var hotwordsBinding: Binding<String> {
        Binding(
            get: { UserDefaults.standard.string(forKey: "asrHotwords") ?? "" },
            set: { UserDefaults.standard.set($0, forKey: "asrHotwords") }
        )
    }
}

// MARK: - Whisper Model Row

private struct WhisperModelRow: View {
    let model: WhisperModelInfo
    let isActive: Bool
    let onActivate: () -> Void
    @ObservedObject private var manager = ModelDownloadManager.shared

    var body: some View {
        HStack(spacing: 10) {
            // Active indicator
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isActive ? .accentColor : Color(nsColor: .tertiaryLabelColor))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName).font(.subheadline).bold()
                    Text(model.fileSizeDisplay)
                        .font(.caption).foregroundColor(.secondary)
                    Text("内存 \(model.ramRequiredMB)MB+")
                        .font(.caption).foregroundColor(.secondary)

                    if !model.supportsRealtime {
                        Text("非实时")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundColor(.orange)
                    }

                    Text(String(repeating: "★", count: model.chineseQuality))
                        .font(.caption).foregroundColor(.orange)
                }
            }

            Spacer()

            // Action button area
            switch manager.downloadState(for: model) {
            case .idle:
                Button("下载") { manager.startDownload(for: model) }
                    .buttonStyle(.bordered).controlSize(.small)
            case .downloading(let p):
                HStack(spacing: 6) {
                    ProgressView(value: p).frame(width: 70)
                    Text("\(Int(p * 100))%").font(.caption2).foregroundColor(.secondary)
                    Button(action: { manager.cancelDownload(for: model) }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            case .verifying:
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text("校验…").font(.caption2).foregroundColor(.secondary)
                }
            case .done:
                if isActive {
                    Text("使用中").font(.caption).foregroundColor(.secondary)
                } else {
                    Button("启用") { onActivate() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            case .failed(_):
                Button("重试") { manager.startDownload(for: model) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ASR Local Content

private struct ASRLocalContent: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var downloadManager = ModelDownloadManager.shared

    /// 返回显式激活的模型 ID。whisperModelPath 为空时返回 nil，
    /// 避免 resolvedWhisperModelPath 的默认 fallback (ggml-small.bin) 导致误判。
    private var activeModelID: String? {
        guard !settings.whisperModelPath.isEmpty else { return nil }
        let path = settings.resolvedWhisperModelPath
        return WhisperModelInfo.all.first { path.hasSuffix($0.fileName) }?.id ?? "custom"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Real-time notice
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text("本地 Whisper 模型仅支持录制完成后统一转录，不支持实时流式识别。如需实时识别请切换至「自定义接口」。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            ForEach(WhisperModelInfo.all) { model in
                WhisperModelRow(
                    model: model,
                    isActive: settings.voiceModelSource == .local && activeModelID == model.id,
                    onActivate: {
                        // 互斥：清除远程 ASR 激活状态
                        settings.activeRemoteASRID = ""
                        settings.whisperModelPath = model.localPath.path
                        settings.voiceModelSource = .local
                    }
                )
                Divider()
            }

            // Custom imported model row
            if settings.voiceModelSource == .local && activeModelID == "custom" {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor).frame(width: 18)
                    Text(URL(fileURLWithPath: settings.whisperModelPath).lastPathComponent)
                        .font(.subheadline).bold()
                    Text("自定义").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("使用中").font(.caption).foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                Divider()
            }

            // Manual import
            Button(action: importCustomModel) {
                Label("手动导入 .bin 文件…", systemImage: "square.and.arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .padding(.top, 2)
        }
    }

    private func importCustomModel() {
        let panel = NSOpenPanel()
        panel.title = "选择 Whisper 模型文件"
        panel.message = "选择一个 ggml .bin 格式的 Whisper 模型文件"
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let src = panel.url else { return }

        let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("TalkType/models")
        let dest = modelsDir.appendingPathComponent(src.lastPathComponent)

        do {
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
            // 互斥：清除远程 ASR 激活状态
            settings.activeRemoteASRID = ""
            settings.whisperModelPath = dest.path
            settings.voiceModelSource = .local
        } catch {
            print("[Import] Failed to copy model: \(error)")
        }
    }
}

// MARK: - ASR Remote Content

private struct ASRRemoteContent: View {
    @ObservedObject private var store = RemoteServiceStore.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.asrServices.filter(\.isPreset)) { service in
                ASRServiceRow(
                    service: service,
                    isActive: settings.voiceModelSource == .remote && settings.activeRemoteASRID == service.id,
                    onActivate: {
                        // 互斥：清除本地模型激活状态
                        settings.whisperModelPath = ""
                        settings.activeRemoteASRID = service.id
                        settings.voiceModelSource = .remote
                    }
                )
                Divider()
            }

            Divider()
            ASRCustomServiceView()
        }
    }
}

// MARK: - ASR Custom Service View

private struct ASRCustomServiceView: View {
    @ObservedObject private var store = RemoteServiceStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var isActivating = false

    private var existingCustom: RemoteService? {
        store.asrServices.first { !$0.isPreset }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isActive ? .accentColor : Color(nsColor: .tertiaryLabelColor))
                    .font(.system(size: 14))

                Text("自定义 ASR 服务")
                    .font(.subheadline).bold()

                Spacer()

                if isActive {
                    Text("使用中").font(.caption).foregroundColor(.secondary)
                } else if isActivating {
                    ProgressView().scaleEffect(0.5).frame(height: 10)
                } else {
                    Button("启用") { activate() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(existingCustom == nil && baseURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            HStack(spacing: 6) {
                Text("地址").font(.caption).foregroundColor(.secondary).frame(width: 55, alignment: .trailing)
                TextField("wss://api.example.com/v1", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onChange(of: baseURL) { _ in saveIfNeeded() }
            }

            HStack(spacing: 6) {
                Text("API Key").font(.caption).foregroundColor(.secondary).frame(width: 55, alignment: .trailing)
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onChange(of: apiKey) { _ in saveIfNeeded() }
            }

            HStack(spacing: 6) {
                Text("模型").font(.caption).foregroundColor(.secondary).frame(width: 55, alignment: .trailing)
                TextField("模型名称", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onChange(of: modelName) { _ in saveIfNeeded() }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            if let custom = existingCustom {
                baseURL = custom.baseURL
                apiKey = custom.apiKey
                modelName = custom.modelName
            }
        }
        .onChange(of: store.asrServices.count) { _ in
            if let custom = existingCustom {
                if baseURL.isEmpty { baseURL = custom.baseURL }
                if apiKey.isEmpty { apiKey = custom.apiKey }
                if modelName.isEmpty { modelName = custom.modelName }
            }
        }
    }

    private var isActive: Bool {
        guard let custom = existingCustom else { return false }
        return settings.voiceModelSource == .remote && settings.activeRemoteASRID == custom.id
    }

    private func saveIfNeeded() {
        guard let custom = existingCustom,
              baseURL != custom.baseURL || apiKey != custom.apiKey || modelName != custom.modelName
        else { return }
        var updated = custom
        updated.baseURL = baseURL
        updated.apiKey = apiKey
        updated.modelName = modelName
        store.updateService(updated)
    }

    private func activate() {
        isActivating = true
        saveIfNeeded()

        if let custom = existingCustom {
            settings.whisperModelPath = ""
            settings.activeRemoteASRID = custom.id
            settings.voiceModelSource = .remote
            isActivating = false
            return
        }

        guard !baseURL.isEmpty else {
            isActivating = false
            return
        }

        let service = RemoteService(
            id: UUID().uuidString,
            name: "自定义 ASR",
            type: .asr,
            baseURL: baseURL,
            apiKey: apiKey,
            modelName: modelName.isEmpty ? "custom" : modelName,
            isPreset: false
        )
        store.addService(service)
        settings.whisperModelPath = ""
        settings.activeRemoteASRID = service.id
        settings.voiceModelSource = .remote
        isActivating = false
    }
}

// MARK: - ASR Service Row

private struct ASRServiceRow: View {
    let service: RemoteService
    let isActive: Bool
    let onActivate: () -> Void
    @ObservedObject private var store = RemoteServiceStore.shared
    @State private var localApiKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isActive ? .accentColor : Color(nsColor: .tertiaryLabelColor))
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(service.name).font(.subheadline).bold()
                        Text("预设").font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundColor(.secondary)
                    }
                    Text(service.baseURL)
                        .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    Text("模型：\(service.modelName)")
                        .font(.caption2).foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if isActive {
                        Text("使用中").font(.caption).foregroundColor(.secondary)
                    } else {
                        Button("启用") { onActivate() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            }

            HStack(spacing: 6) {
                Text("API Key").font(.caption).foregroundColor(.secondary).frame(width: 55, alignment: .trailing)
                SecureField("API Key", text: $localApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onChange(of: localApiKey) { _ in
                        guard localApiKey != service.apiKey else { return }
                        var updated = service
                        updated.apiKey = localApiKey
                        store.updateService(updated)
                    }
            }
        }
        .padding(.vertical, 4)
        .onAppear { localApiKey = service.apiKey }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let onRequest: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(isGranted ? .green : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                Label("已授权", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Button("开启") {
                    onRequest()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.blue)
            }
        }
    }
}

// MARK: - LLM service list

private struct LLMServiceList: View {
    @ObservedObject private var store = RemoteServiceStore.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.llmServices.filter(\.isPreset)) { service in
                LLMServiceRow(
                    service: service,
                    isActive: settings.activeRemoteLLMID == service.id,
                    onActivate: { settings.activeRemoteLLMID = service.id }
                )
                Divider()
            }

            Divider()
            LLMCustomServiceView()
        }
    }
}

private struct LLMServiceRow: View {
    let service: RemoteService
    let isActive: Bool
    let onActivate: () -> Void
    @ObservedObject private var store = RemoteServiceStore.shared
    @State private var localApiKey: String = ""
    @State private var localModelName: String = ""
    @State private var verifyState: VerifyState = .idle

    private enum VerifyState: Equatable {
        case idle, verifying, success, failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isActive ? .accentColor : Color(nsColor: .tertiaryLabelColor))
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(service.name).font(.subheadline).bold()
                        Text("预设").font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundColor(.secondary)
                    }
                    Text(service.baseURL)
                        .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if isActive {
                        Text("使用中").font(.caption).foregroundColor(.secondary)
                    } else {
                        Button("启用") { onActivate() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            }

            HStack(spacing: 6) {
                Text("API Key").font(.caption).foregroundColor(.secondary).frame(width: 55, alignment: .trailing)
                SecureField("API Key", text: $localApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onChange(of: localApiKey) { _ in
                        guard localApiKey != service.apiKey else { return }
                        var updated = service
                        updated.apiKey = localApiKey
                        store.updateService(updated)
                    }
            }

            HStack(spacing: 6) {
                Text("模型").font(.caption).foregroundColor(.secondary).frame(width: 55, alignment: .trailing)
                TextField("模型名称", text: $localModelName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onChange(of: localModelName) { _ in
                        guard localModelName != service.modelName else { return }
                        var updated = service
                        updated.modelName = localModelName
                        store.updateService(updated)
                    }

                verifyControl
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            localApiKey = service.apiKey
            localModelName = service.modelName
        }
    }

    @ViewBuilder
    private var verifyControl: some View {
        switch verifyState {
        case .idle:
            Button("验证") {
                Task { await runVerification() }
            }
            .buttonStyle(.bordered).controlSize(.small).font(.caption)
        case .verifying:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.5).frame(height: 10)
                Text("验证中…").font(.caption2).foregroundColor(.secondary)
            }
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green).font(.caption)
        case .failed(let msg):
            Text(msg).font(.caption2).foregroundColor(.red).lineLimit(1)
        }
    }

    private func runVerification() async {
        verifyState = .verifying
        if localApiKey != service.apiKey || localModelName != service.modelName {
            var updated = service
            updated.apiKey = localApiKey
            updated.modelName = localModelName
            store.updateService(updated)
        }
        let config = LLMEngine.Config(
            baseURL: service.baseURL,
            apiKey: localApiKey,
            model: localModelName,
            maxTokens: 10,
            temperature: 0.3
        )
        let engine = LLMEngine(config: config)
        let available = await engine.checkAvailability()
        verifyState = available ? .success : .failed("连接失败")
        if available {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            verifyState = .idle
        }
    }
}

// MARK: - LLM Custom Service View

private struct LLMCustomServiceView: View {
    @ObservedObject private var store = RemoteServiceStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var isActivating = false
    @State private var verifyState: VerifyState = .idle

    private enum VerifyState: Equatable {
        case idle, verifying, success, failed(String)
    }

    private var existingCustom: RemoteService? {
        store.llmServices.first { !$0.isPreset }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isActive ? .accentColor : Color(nsColor: .tertiaryLabelColor))
                    .font(.system(size: 14))

                Text("自定义 LLM 服务")
                    .font(.subheadline).bold()

                Spacer()

                if isActive {
                    Text("使用中").font(.caption).foregroundColor(.secondary)
                } else if isActivating {
                    ProgressView().scaleEffect(0.5).frame(height: 10)
                } else {
                    Button("启用") { activate() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(existingCustom == nil && baseURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                verifyControl
            }

            HStack(spacing: 6) {
                Text("地址").font(.caption).foregroundColor(.secondary).frame(width: 55, alignment: .trailing)
                TextField("http://127.0.0.1:8080/v1", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onChange(of: baseURL) { _ in saveIfNeeded() }
            }

            HStack(spacing: 6) {
                Text("API Key").font(.caption).foregroundColor(.secondary).frame(width: 55, alignment: .trailing)
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onChange(of: apiKey) { _ in saveIfNeeded() }
            }

            HStack(spacing: 6) {
                Text("模型").font(.caption).foregroundColor(.secondary).frame(width: 55, alignment: .trailing)
                TextField("模型名称", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onChange(of: modelName) { _ in saveIfNeeded() }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            if let custom = existingCustom {
                baseURL = custom.baseURL
                apiKey = custom.apiKey
                modelName = custom.modelName
            }
        }
    }

    private var isActive: Bool {
        guard let custom = existingCustom else { return false }
        return settings.activeRemoteLLMID == custom.id
    }

    @ViewBuilder
    private var verifyControl: some View {
        switch verifyState {
        case .idle:
            Button("验证") {
                Task { await runVerification() }
            }
            .buttonStyle(.bordered).controlSize(.small).font(.caption)
        case .verifying:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.5).frame(height: 10)
                Text("验证中…").font(.caption2).foregroundColor(.secondary)
            }
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green).font(.caption)
        case .failed(let msg):
            Text(msg).font(.caption2).foregroundColor(.red).lineLimit(1)
        }
    }

    private func saveIfNeeded() {
        guard let custom = existingCustom,
              baseURL != custom.baseURL || apiKey != custom.apiKey || modelName != custom.modelName
        else { return }
        var updated = custom
        updated.baseURL = baseURL
        updated.apiKey = apiKey
        updated.modelName = modelName
        store.updateService(updated)
    }

    private func runVerification() async {
        verifyState = .verifying
        saveIfNeeded()
        let config = LLMEngine.Config(
            baseURL: baseURL,
            apiKey: apiKey,
            model: modelName,
            maxTokens: 10,
            temperature: 0.3
        )
        let engine = LLMEngine(config: config)
        let ok = await engine.checkAvailability()
        verifyState = ok ? .success : .failed("连接失败")
        if ok {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            verifyState = .idle
        }
    }

    private func activate() {
        isActivating = true
        saveIfNeeded()

        if let custom = existingCustom {
            settings.activeRemoteLLMID = custom.id
            isActivating = false
            return
        }

        guard !baseURL.isEmpty else {
            isActivating = false
            return
        }

        let service = RemoteService(
            id: UUID().uuidString,
            name: "自定义 LLM",
            type: .llm,
            baseURL: baseURL,
            apiKey: apiKey,
            modelName: modelName.isEmpty ? "custom" : modelName,
            isPreset: false
        )
        store.addService(service)
        settings.activeRemoteLLMID = service.id
        isActivating = false
    }
}
