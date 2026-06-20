import SwiftUI
import AVFoundation

// Four-step onboarding shown on first launch.
struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var step = 0
    @ObservedObject private var downloadManager = ModelDownloadManager.shared
    @ObservedObject private var settings = AppSettings.shared

    private let compatibility = CompatibilityChecker.run()

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<4) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 24)

            Spacer()

            Group {
                switch step {
                case 0: stepWelcome
                case 1: stepMicrophone
                case 2: stepModel
                case 3: stepHotkey
                default: EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 0.25), value: step)

            Spacer()

            // Navigation buttons
            HStack {
                if step > 0 {
                    Button("上一步") { step -= 1 }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(step < 3 ? "下一步" : "开始使用") {
                    if step < 3 { step += 1 } else { isComplete = true }
                }
                .buttonStyle(.borderedProminent)
                .disabled(step == 2 && !hasDownloadedModel)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(width: 520, height: 420)
    }

    // MARK: - Steps

    private var stepWelcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)
            Text("欢迎使用 TalkType")
                .font(.largeTitle).bold()
            Text("本地隐私语音输入法\n音频在设备本地处理，永不上传")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if compatibility.hasWarnings {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(compatibility.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(12)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 40)
    }

    private var stepMicrophone: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 52))
                .foregroundColor(.accentColor)
            Text("授权麦克风")
                .font(.title).bold()
            Text("TalkType 需要麦克风权限才能录音。\n音频仅在本设备处理，不会发送到任何服务器。")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("授权麦克风权限") {
                requestMicrophonePermission()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 40)
    }

    private var stepModel: some View {
        VStack(spacing: 12) {
            Text("下载语音识别模型")
                .font(.title2).bold()
            Text("选择并下载一个 Whisper 模型。模型越大识别越准，但需要更多内存和时间。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(WhisperModelInfo.all) { model in
                        ModelRowView(model: model, isRecommended: model.id == compatibility.suggestedModelID)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 8)
    }

    private var stepHotkey: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 52))
                .foregroundColor(.accentColor)
            Text("全局热键")
                .font(.title).bold()

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    keyBadge("⌥")
                    Text("+").font(.title2).foregroundColor(.secondary)
                    keyBadge("Space")
                }
                Text("在任意 App 中按住热键说话，松开后文字自动插入光标位置。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("可在偏好设置中修改热键。")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Helpers

    private var hasDownloadedModel: Bool {
        WhisperModelInfo.all.contains { $0.isDownloaded }
    }

    private func keyBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        if #available(macOS 14, *) {
            AVAudioApplication.requestRecordPermission { _ in }
        }
    }
}

// MARK: - Model row

private struct ModelRowView: View {
    let model: WhisperModelInfo
    let isRecommended: Bool
    @ObservedObject private var manager = ModelDownloadManager.shared

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName).font(.headline)
                    if isRecommended {
                        Text("推荐").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundColor(.accentColor)
                    }
                }
                HStack(spacing: 8) {
                    Text(model.fileSizeDisplay).font(.caption).foregroundColor(.secondary)
                    Text("内存 \(model.ramRequiredMB)MB+").font(.caption).foregroundColor(.secondary)
                    Text(String(repeating: "★", count: model.chineseQuality)).font(.caption).foregroundColor(.orange)
                }
            }
            Spacer()
            stateView
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var stateView: some View {
        switch manager.downloadState(for: model) {
        case .idle:
            Button("下载") { manager.startDownload(for: model) }
                .buttonStyle(.bordered).controlSize(.small)
        case .downloading(let p):
            HStack(spacing: 8) {
                ProgressView(value: p).frame(width: 80)
                Text("\(Int(p * 100))%").font(.caption).foregroundColor(.secondary)
                Button(action: { manager.cancelDownload(for: model) }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        case .verifying:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text("校验中…").font(.caption).foregroundColor(.secondary)
            }
        case .done:
            Label("已下载", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundColor(.green)
        case .failed(_):
            VStack(alignment: .trailing, spacing: 2) {
                Text("失败").font(.caption).foregroundColor(.red)
                Button("重试") { manager.startDownload(for: model) }
                    .font(.caption2).buttonStyle(.plain).foregroundColor(.accentColor)
            }
        }
    }
}
