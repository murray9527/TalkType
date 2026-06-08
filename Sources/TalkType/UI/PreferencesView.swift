import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedTab = "general"

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tabItem { Label("通用", systemImage: "gear") }
                .tag("general")

            ModelsTab()
                .tabItem { Label("模型", systemImage: "cpu") }
                .tag("models")
        }
        .frame(width: 480, height: 320)
    }
}

private struct GeneralTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("语音识别") {
                Picker("识别语言", selection: $settings.language) {
                    Text("中文").tag("zh")
                    Text("英文").tag("en")
                    Text("自动检测").tag("auto")
                }
            }

            Section("语气转换") {
                Picker("转换风格", selection: $settings.toneStyleRaw) {
                    ForEach(ToneStyle.allCases) { style in
                        Text(style.rawValue).tag(style.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                if settings.isToneConversionEnabled {
                    Text("启用后，识别完成将弹出选择框，可选基础文本或风格文本。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct ModelsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Whisper 语音识别模型") {
                HStack {
                    TextField("模型文件路径 (.bin)", text: $settings.whisperModelPath)
                        .textFieldStyle(.roundedBorder)
                    Button("选择…") {
                        let panel = NSOpenPanel()
                        panel.allowsOtherFileTypes = true
                        panel.message = "选择 Whisper .bin 模型文件"
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.whisperModelPath = url.path
                        }
                    }
                }
                Text("默认：\(settings.resolvedWhisperModelPath)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("语气转换 LLM 服务") {
                TextField("API 地址", text: $settings.llmBaseURL)
                    .textFieldStyle(.roundedBorder)
                TextField("模型名称（可留空）", text: $settings.llmModel)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key（本地服务可留空）", text: $settings.llmApiKey)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Text("支持任何 OpenAI 兼容接口：").font(.caption).foregroundStyle(.secondary)
                    Text("• 本地 llama-server：http://127.0.0.1:8080").font(.caption2).foregroundStyle(.tertiary)
                    Text("• Ollama：http://127.0.0.1:11434/v1 + 模型名 qwen2.5:1.5b").font(.caption2).foregroundStyle(.tertiary)
                    Text("• DeepSeek / 其他云端 API：填入对应地址和 Key").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
