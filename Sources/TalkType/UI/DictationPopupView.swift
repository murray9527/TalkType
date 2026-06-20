import SwiftUI

// MARK: - NSTextView Wrapper

struct DictationTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: -4)

        let textView = NSTextView()
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 15)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.delegate = context.coordinator
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }
        func textDidChange(_ notification: Notification) {
            if let tv = notification.object as? NSTextView { text = tv.string }
        }
    }
}

// MARK: - Layer Card

private struct LayerCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            content
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

// MARK: - Popup View

struct DictationPopupView: View {
    @ObservedObject var state: PopupState

    private var ds: DictationState { state.dictationState }
    private var isReady: Bool { ds == .ready }
    private var hasText: Bool { !state.text.isEmpty }
    private var hasOptimized: Bool { (state.styledText?.isEmpty == false) }
    private var hasRoast: Bool { (state.roastText?.isEmpty == false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Layer 1: Top status bar (always visible)
            topBar

            // Layer 2: Recognition text (appears during/after recording)
            if hasText {
                layerDivider
                textLayer
            }

            // Layer 3: Text optimization — always visible when optimization or roast is active
            if isReady, hasOptimized || state.isOptimizing || hasRoast || state.isRoasting {
                layerDivider
                optimizeLayer
            }

            // Emotion bar — below everything
            if isReady, let emotion = state.detectedEmotion, emotion != .neutral, !emotion.friendlyMessage.isEmpty {
                layerDivider
                empathyBanner(emotion: emotion)
            }
        }
        .frame(width: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.25), radius: 32, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var layerDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
    }
}

// MARK: - Layer 1: Top Bar

private extension DictationPopupView {
    var topBar: some View {
        HStack(spacing: 8) {
            // Left: status
            HStack(spacing: 8) {
                if ds.showSpinner {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }

                if !state.modelLabel.isEmpty {
                    Text(state.modelLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor, in: Capsule())
                }

                Text(ds.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                if ds.showSpinner {
                    let secs = ds == .processing ? state.processingSeconds : state.elapsedSeconds
                    Text("\(secs)s")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(secs >= 50 ? Color.orange : Color(nsColor: .tertiaryLabelColor))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Emotion + Empathy Bar (combined)

private extension DictationPopupView {
    func empathyBanner(emotion: ASREmotion) -> some View {
        HStack(spacing: 10) {
            Label(emotion.displayName, systemImage: emotion.isPositive ? "face.smiling" : "face.dashed")
                .font(.caption2.weight(.medium))
                .foregroundStyle(emotion.isPositive ? .green : .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((emotion.isPositive ? Color.green : Color.orange).opacity(0.1), in: Capsule())

            Text(emotion.friendlyMessage)
                .font(.subheadline.weight(.medium))

            if emotion.canRoast {
                Button {
                    state.roastText = nil
                    state.isRoasting = true
                    state.onRoast?(state.text)
                } label: {
                    HStack(spacing: 4) {
                        Text("帮我怼")
                            .font(.caption.weight(.semibold))
                        Text("😡")
                            .font(.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.red.opacity(0.8)))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            (emotion.isPositive ? Color.green : Color.orange).opacity(0.08)
        )
    }
}

// MARK: - Floating Insert Button

private extension DictationPopupView {
    func insertButton(action: @escaping () -> Void, shortcutHint: String) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 4) {
                Text(shortcutHint)
                    .font(.caption2.weight(.medium))
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .padding(10)
    }
}

// MARK: - Layer 2: Recognition Text

private extension DictationPopupView {
    var textLayer: some View {
        LayerCard(title: "识别结果", icon: "waveform") {
            ZStack(alignment: .bottomTrailing) {
                DictationTextView(text: $state.text, isEditable: isReady)
                    .frame(minHeight: 100, maxHeight: 200)

                if isReady {
                    insertButton(action: { state.onConfirm(state.text) }, shortcutHint: "⇧⌘↩")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Layer 3: Text Optimization

private extension DictationPopupView {
    var optimizeLayer: some View {
        let displayText = state.roastText ?? state.styledText
        let layerTitle = hasRoast ? "怼人 💢" : "优化结果"
        let layerIcon = hasRoast ? "flame.fill" : "sparkle.magnifyingglass"

        return VStack(alignment: .leading, spacing: 8) {
            // Style picker — always visible, never affected by roast mode
            HStack(spacing: 8) {
                Text("转换风格")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("风格", selection: $state.currentTone) {
                    ForEach(ToneStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .onChange(of: state.currentTone) { _ in
                    Task { @MainActor in
                        AppSettings.shared.toneStyle = state.currentTone
                    }
                    state.roastText = nil  // clear temporary roast
                    state.styledText = nil
                    state.isOptimizing = true
                    state.onReoptimize?(state.text)
                }

                if hasOptimized || hasRoast {
                    Button {
                        state.roastText = nil  // clear roast, revert to normal optimization
                        state.styledText = nil
                        state.isOptimizing = true
                        state.onReoptimize?(state.text)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                            Text("重新优化")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            // Text box — loading overlay when optimising/roasting, floating insert button
            LayerCard(title: layerTitle, icon: layerIcon) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        DictationTextView(
                            text: Binding(
                                get: { displayText ?? "" },
                                set: { if !hasRoast { state.styledText = $0 } }
                            ),
                            isEditable: isReady && !hasRoast
                        )
                        .frame(minHeight: 100, maxHeight: 200)

                        if state.isOptimizing || state.isRoasting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(state.isRoasting ? "正在怼人…" : "正在优化…")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.regularMaterial)
                        }
                    }

                    if isReady, let text = displayText, !text.isEmpty {
                        insertButton(action: { state.onConfirm(text) }, shortcutHint: "⌘↩")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
