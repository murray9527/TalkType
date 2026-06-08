import SwiftUI
import AppKit

// Floating popup shown after transcription when tone conversion is enabled.
// Displays basic text immediately; styled text appears async as LLM finishes.
struct ResultPopupView: View {
    let basicText: String
    @Binding var styledText: String?   // nil = LLM still loading
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    @State private var autoInsertCountdown = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            option(label: "基础", text: basicText, key: "1", isReady: true)
            Divider()
            option(label: "风格", text: styledText, key: "2", isReady: styledText != nil)
        }
        .frame(width: 420)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 16)
        .onAppear { startCountdown() }
    }

    private var header: some View {
        HStack {
            Text("选择文本")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("自动插入 \(autoInsertCountdown)s")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button("取消") { onDismiss() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func option(label: String, text: String?, key: String, isReady: Bool) -> some View {
        Button {
            if let text { onSelect(text) }
        } label: {
            HStack(spacing: 10) {
                Text(key)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                if isReady, let text {
                    Text(text)
                        .font(.body)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("转换中…").foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isReady)
    }

    private func startCountdown() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if autoInsertCountdown <= 1 {
                timer.invalidate()
                onSelect(basicText)
            } else {
                autoInsertCountdown -= 1
            }
        }
    }
}
