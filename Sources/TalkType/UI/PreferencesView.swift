import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                asrSection
                hotwordsSection
                hotkeySection
                optimizationSection
                if settings.textOptimizationEnabled {
                    llmSection
                }
            }
            .padding()
        }
        .frame(width: 560, height: 520)
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
                case .subscription:
                    SubscriptionRow()
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

                Picker("转换来源", selection: $settings.refinementModelSourceRaw) {
                    ForEach(RefinementModelSource.allCases) { source in
                        Text(source.displayName).tag(source.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                switch settings.refinementModelSource {
                case .local:
                    VStack(spacing: 8) {
                        Image(systemName: "tray.full")
                            .font(.title2).foregroundColor(.secondary)
                        Text("当前版本暂不支持本地语气转换模型")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("请选择「自定义接口」以接入云端或自部署的 LLM 服务")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                case .remote:
                    LLMServiceList()
                case .subscription:
                    SubscriptionPlaceholder()
                }
            }
            .padding(8)
        }
    }

    /// Hotword text saved to corpusText on ASR Config.
    private var hotwordsBinding: Binding<String> {
        Binding(
            get: { UserDefaults.standard.string(forKey: "asrHotwords") ?? "" },
            set: { UserDefaults.standard.set($0, forKey: "asrHotwords") }
        )
    }
}

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

    private var activeModelID: String {
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
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.asrServices) { service in
                ASRServiceRow(
                    service: service,
                    isActive: settings.voiceModelSource == .remote && settings.activeRemoteASRID == service.id,
                    onActivate: {
                        settings.activeRemoteASRID = service.id
                        settings.voiceModelSource = .remote
                    }
                )
                if service.id != store.asrServices.last?.id {
                    Divider()
                }
            }

            HStack {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("添加自定义服务…", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                Text("支持 WebSocket 实时语音识别接口")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddASRServiceSheet()
        }
    }
}

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
                        if service.isPreset {
                            Text("预设").font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .foregroundColor(.secondary)
                        }
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
                    if !service.isPreset {
                        Button(role: .destructive) {
                            store.deleteService(id: service.id)
                        } label: {
                            Text("删除").font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // API key row
            HStack(spacing: 6) {
                Text("API Key").font(.caption).foregroundColor(.secondary).frame(width: 55, alignment: .trailing)
                SecureField(service.isPreset ? "填入你的 API Key" : "API Key", text: $localApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("保存") {
                    var updated = service
                    updated.apiKey = localApiKey
                    store.updateService(updated)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .font(.caption)
                .disabled(localApiKey == service.apiKey)
            }
        }
        .padding(.vertical, 4)
        .onAppear { localApiKey = service.apiKey }
    }
}

private struct AddASRServiceSheet: View {
    @ObservedObject private var store = RemoteServiceStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var baseURL = ""
    @State private var modelName = ""
    @State private var apiKey = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("添加自定义 ASR 服务")
                .font(.headline)

            Form {
                TextField("名称（如 My ASR）", text: $name)
                TextField("API 地址（如 wss://api.example.com/v1）", text: $baseURL)
                TextField("模型名称", text: $modelName)
                SecureField("API Key（可选）", text: $apiKey)
            }
            .formStyle(.grouped)

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("添加") {
                    let service = RemoteService(
                        id: UUID().uuidString,
                        name: name.isEmpty ? "自定义 ASR" : name,
                        type: .asr,
                        baseURL: baseURL,
                        apiKey: apiKey,
                        modelName: modelName,
                        isPreset: false
                    )
                    store.addService(service)
                    settings.activeRemoteASRID = service.id
                    settings.voiceModelSource = .remote
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(baseURL.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 280)
    }
}

// MARK: - Subscription Placeholder

private struct SubscriptionPlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.title2).foregroundColor(.secondary)
            Text("官方订阅服务即将推出")
                .font(.subheadline).foregroundColor(.secondary)
            Text("敬请期待")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct SubscriptionRow: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button {
            settings.voiceModelSource = .subscription
        } label: {
            HStack(spacing: 10) {
                Image(systemName: settings.voiceModelSource == .subscription
                    ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(settings.voiceModelSource == .subscription
                        ? .accentColor : Color(nsColor: .tertiaryLabelColor))
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text("官方订阅服务").font(.subheadline).bold()
                    Text("即将推出，敬请期待")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if settings.voiceModelSource == .subscription {
                    Text("使用中").font(.caption).foregroundColor(.secondary)
                } else {
                    Text("敬请期待").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - LLM service list

private struct LLMServiceList: View {
    @ObservedObject private var store = RemoteServiceStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.llmServices) { service in
                LLMServiceRow(
                    service: service,
                    isActive: settings.activeRemoteLLMID == service.id,
                    onActivate: { settings.activeRemoteLLMID = service.id }
                )
                if service.id != store.llmServices.last?.id {
                    Divider()
                }
            }

            HStack {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("添加自定义服务…", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                Text("支持任何 OpenAI 兼容接口（Ollama、DeepSeek、阿里云等）")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddLLMServiceSheet()
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
        case idle
        case verifying
        case success
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: icon, name, URL, actions
            HStack(spacing: 10) {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isActive ? .accentColor : Color(nsColor: .tertiaryLabelColor))
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(service.name).font(.subheadline).bold()
                        if service.isPreset {
                            Text("预设").font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .foregroundColor(.secondary)
                        }
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
                    if !service.isPreset {
                        Button(role: .destructive) {
                            store.deleteService(id: service.id)
                        } label: {
                            Text("删除").font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // API key row
            HStack(spacing: 6) {
                Text("API Key").font(.caption).foregroundColor(.secondary).frame(width: 55, alignment: .trailing)
                SecureField(service.isPreset ? "填入你的 API Key" : "API Key", text: $localApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("保存") {
                    var updated = service
                    updated.apiKey = localApiKey
                    store.updateService(updated)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .font(.caption)
                .disabled(localApiKey == service.apiKey)
            }

            // Editable model name row
            HStack(spacing: 6) {
                Text("模型").font(.caption).foregroundColor(.secondary).frame(width: 55, alignment: .trailing)
                TextField("模型名称", text: $localModelName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("保存") {
                    var updated = service
                    updated.modelName = localModelName
                    store.updateService(updated)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .font(.caption)
                .disabled(localModelName == service.modelName)

                // Verify button
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
            .buttonStyle(.bordered).controlSize(.small)
            .font(.caption)
        case .verifying:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.5).frame(height: 10)
                Text("验证中…").font(.caption2).foregroundColor(.secondary)
            }
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green).font(.caption)
        case .failed(let msg):
            Text(msg)
                .font(.caption2).foregroundColor(.red)
                .lineLimit(1)
        }
    }

    private func runVerification() async {
        verifyState = .verifying

        // Save pending edits before verifying
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

        if available {
            verifyState = .success
            // Auto-reset after 1.5s
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            verifyState = .idle
        } else {
            verifyState = .failed("连接失败")
        }
    }
}

private struct AddLLMServiceSheet: View {
    @ObservedObject private var store = RemoteServiceStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var baseURL = ""
    @State private var modelName = ""
    @State private var apiKey = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("添加自定义 LLM 服务")
                .font(.headline)

            Form {
                TextField("名称（如 My LLM）", text: $name)
                TextField("API 地址（如 http://127.0.0.1:8080）", text: $baseURL)
                TextField("如 qwen-flash、deepseek-v4-flash", text: $modelName)
                SecureField("API Key（可选）", text: $apiKey)
            }
            .formStyle(.grouped)

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("添加") {
                    let service = RemoteService(
                        id: UUID().uuidString,
                        name: name.isEmpty ? "自定义 LLM" : name,
                        type: .llm,
                        baseURL: baseURL,
                        apiKey: apiKey,
                        modelName: modelName,
                        isPreset: false
                    )
                    store.addService(service)
                    settings.activeRemoteLLMID = service.id
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(baseURL.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 280)
    }
}
