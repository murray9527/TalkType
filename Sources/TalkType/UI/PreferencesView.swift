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
        VStack(alignment: .leading, spacing: 12) {
            Text("Whisper 模型路径")
                .font(.headline)

            HStack {
                TextField("模型文件路径 (.bin)", text: $settings.whisperModelPath)
                    .textFieldStyle(.roundedBorder)
                Button("选择…") {
                    selectModelFile()
                }
            }

            Text("当前模型：\(settings.whisperModelPath.isEmpty ? "未选择" : URL(fileURLWithPath: settings.whisperModelPath).lastPathComponent)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("模型下载功能将在后续版本中加入。")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding()
    }

    private func selectModelFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.message = "选择 Whisper .bin 模型文件"
        if panel.runModal() == .OK, let url = panel.url {
            AppSettings.shared.whisperModelPath = url.path
        }
    }
}
