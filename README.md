# TalkType

**Privacy-first local voice input for macOS.** Dictation in Chinese and English. Run fully offline with Whisper, or use remote ASR/LLM services for real-time streaming and tone conversion.

---

## Features

- 🎤 **Push-to-talk** — press-and-hold a global hotkey to record, release to transcribe
- 🏠 **Fully offline** — local Whisper model, no network required (voice stays on your machine)
- 🌐 **Remote ASR** — real-time streaming recognition via Qwen-ASR WebSocket (阿里云 DashScope)
- 🤖 **LLM tone conversion** — rewrite your text with one of 6 styles (formal, concise, polite, oral, gentle, ambiguous)
- 🔥 **Roast mode** — aggressively rewrite text for, well, roasting people
- ✏️ **Editable popup** — edit the transcription before inserting
- ⌨️ **Hotkey configurable** — choose any global shortcut for push-to-talk
- 📦 **Self-contained** — one app, zero daemons

---

## Pipeline

```
Record ─► ASR ─► Clean ─► (optional) LLM optimize ─► Insert

  ↓          ↓           ↓               ↓               ↓
 Audio     Whisper    strip fillers    6 tone styles    Cmd-V
Recorder  or Remote  + deduplicate     or roast        via CGEvent
```

### Components

| Component | File | Role |
|---|---|---|
| AudioRecorder | `Audio/AudioRecorder.swift` | AVAudioEngine captures mic input, converts to 16kHz mono PCM |
| WhisperEngine | `ASR/WhisperEngine.swift` | local transcription via whisper.cpp C API (actor) |
| RemoteASREngine | `ASR/RemoteASREngine.swift` | Qwen-ASR WebSocket client for real-time streaming |
| LLMEngine | `LLM/LLMEngine.swift` | OpenAI-compatible chat completions HTTP client |
| TextInserter | `UI/TextInserter.swift` | Cmd-V simulation via CGEvent + pasteboard restoration |
| DictationController | `App/DictationController.swift` | Orchestrates the full pipeline (MainActor singleton) |
| PopupWindowController | `UI/PopupWindowController.swift` | NSPanel floating popup with editable text |
| DictationPopupView | `UI/DictationPopupView.swift` | SwiftUI popup with three-phase UI, tone selector, roast button |
| TextOptimizer | `TextProcessing/TextOptimizer.swift` | LLM-powered text optimization with emotion awareness |

---

## Project Structure

```
Sources/TalkType/
├── App/
│   ├── TalkTypeApp.swift            # @main SwiftUI App
│   ├── AppDelegate.swift            # NSApp configuration, status bar, menus
│   ├── DictationController.swift    # Pipeline orchestrator
│   └── HotkeyManager.swift          # Carbon EventHotKey global hotkey
├── Audio/
│   └── AudioRecorder.swift          # AVAudioEngine capture
├── ASR/
│   ├── WhisperEngine.swift          # whisper.cpp actor (local)
│   └── RemoteASREngine.swift        # Qwen-ASR WebSocket (remote)
├── LLM/
│   └── LLMEngine.swift              # OpenAI-compatible HTTP client
├── TextProcessing/
│   ├── ToneStyle.swift              # Tone style enum + system prompts
│   └── TextOptimizer.swift          # LLM optimization with emotion context
├── UI/
│   ├── DictationPopupView.swift     # Main popup SwiftUI view
│   ├── PopupWindowController.swift   # NSPanel window management
│   ├── PreferencesView.swift        # Settings UI
│   ├── OnboardingView.swift         # First-launch wizard
│   ├── HotkeyRecorderView.swift     # Interactive hotkey recorder
│   └── TextInserter.swift           # CGEvent Cmd-V simulation
└── Models/
    ├── AppSettings.swift            # @AppStorage-backed settings singleton
    ├── RemoteServiceStore.swift     # GRDB-backed remote service configs
    ├── ModelDownloadManager.swift   # Whisper model downloader
    ├── DictationTimer.swift         # Timer utility for popup display
    └── CompatibilityChecker.swift   # System capability checks
```

---

## Quick Start

### Prerequisites

- macOS 13+
- Xcode 15+ / Swift 6.0

### Build & Run

```bash
# Clone
git clone https://github.com/YOUR_ACCOUNT/TalkType.git
cd TalkType

# Build
swift build

# Run
swift run
```

> **Note:** The first build downloads and compiles whisper.cpp, which takes a few minutes.

### Use with local Whisper model

```bash
# Download a model (480MB small model recommended)
mkdir -p ~/Library/Application\ Support/TalkType/models
curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin \
     -o ~/Library/Application\ Support/TalkType/models/ggml-small.bin
```

Then launch the app and select **本地模型** in Preferences → ASR settings.

### Use with remote ASR + LLM

1. Open Preferences → ASR → select **自定义接口**
2. Choose a preset (阿里云 Qwen-ASR) or add your own
3. Enter your API key
4. Enable **文本优化** and select a tone style under the LLM section

Supported LLM providers: any OpenAI-compatible API (DeepSeek, 阿里云 DashScope, 小米 MiMo, local Ollama/llama-server, etc.)

---

## Subscription

TalkType will offer a **subscription service** for users who want a zero-configuration experience:

- No API keys to set up
- Pre-configured ASR + LLM endpoints
- Usage tracking and management

> Coming soon. For now, bring your own API keys or use the local Whisper model.

---

## Architecture Notes

- **Swift 6** with strict concurrency checking. WhisperEngine and LLMEngine are actors; blocking C calls run on detached tasks.
- **Push-to-talk** uses Carbon EventHotKey. Key-down starts recording, key-up stops and transcribes.
- **AudioRecorder** creates a fresh AVAudioEngine per session with AVAudioConverter for 16kHz output.
- **RemoteASREngine** uses URLSession WebSocket with server-side VAD for real-time streaming.
- **TextInserter** requires Accessibility permission (System Settings → Privacy → Accessibility).
- **Popup** is an NSPanel with `.nonactivatingPanel` (no focus steal) and `.statusBar` level.

---

## Roadmap

| Feature | Status |
|---|---|
| Local Whisper transcription | ✅ |
| Remote Qwen-ASR streaming | ✅ |
| LLM tone conversion (OpenAI-compatible) | ✅ |
| Editable popup with tone selector | ✅ |
| Hotword / contextual biasing | ✅ |
| Emotion detection from ASR | ✅ |
| Roast mode | ✅ |
| Onboarding wizard | ✅ |
| Model download manager | ✅ |
| System compatibility check | ✅ |
| Official subscription service | 🔜 |
| App bundle distribution (DMG) | 🔜 |
| Website | 🔜 |

---

## License

[MIT](LICENSE)

Copyright (c) 2025 TalkType
