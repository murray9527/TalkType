# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- **Build & run**: `swift run` (or `swift build` to build only)
- **Run tests**: `swift test`
- **Xcode project**: `open Package.swift` (SPM generates the Xcode project)
- **Swift version**: 6.0, with `-parse-as-library` flag

## Architecture Overview

TalkType is a macOS menu-bar app (no dock icon) for privacy-first local voice input. The pipeline is:

**Record → ASR → Rule-based correction → (optional) LLM tone conversion → Insert text**

### Pipeline components (execution order)

| Component | File | Role |
|---|---|---|
| AudioRecorder | `Audio/AudioRecorder.swift` | AVAudioEngine captures mic input, converts to 16kHz mono PCM float32 |
| WhisperEngine | `ASR/WhisperEngine.swift` | Swift actor wrapping whisper.cpp C API for transcription |
| TextPostProcessor | `TextProcessing/TextPostProcessor.swift` | Rule engine: strips Chinese fillers, deduplicates repeated words, adds punctuation |
| LLMEngine | `LLM/LLMEngine.swift` | Swift actor calling any OpenAI-compatible chat completions HTTP API |
| TextInserter | `UI/TextInserter.swift` | Cmd-V simulation via CGEvent + pasteboard restoration |
| DictationController | `App/DictationController.swift` | Orchestrates the full pipeline (MainActor singleton) |

### App structure

- **TalkTypeApp.swift** — `@main` entry, opens Settings scene (no main window)
- **AppDelegate.swift** — `NSApplicationDelegateAdaptor`: status bar icon with menu, hotkey setup, onboarding launch
- **HotkeyManager.swift** — Carbon `EventHotKey` global hotkey, push-to-talk (key down/up callbacks)
- **PopupWindowController** + **ResultPopupView** — `NSPanel` floating popup shown when tone conversion is on; shows basic text immediately, styled text appears asynchronously, auto-inserts after 5s countdown

### Data & Persistence

- **AppSettings.swift** — `@AppStorage`-backed settings singleton (hotkey, language, model path, etc.)
- **RemoteServiceStore** — `@Published` singleton backed by GRDB (SQLite at `~/Library/Application Support/TalkType/services.db`); stores ASR/LLM remote service configurations with presets
- **ModelDownloadManager** — `URLSessionDownloadDelegate` for downloading Whisper models from huggingface
- **CompatibilityChecker** — System capability check (RAM, Apple Silicon, disk space, macOS version)

### UI files

- **PreferencesView.swift** — Tabbed settings (General + Models tabs), includes Whisper model rows with download/activate UI and LLM service CRUD with inline API key management
- **OnboardingView.swift** — 4-step first-launch wizard (welcome → mic permission → model download → hotkey)
- **HotkeyRecorderView.swift** — Interactive hotkey recorder UI with Carbon modifier conversion
- **WhisperModelInfo** — Struct defining downloadable model metadata (tiny/base/small/medium/large-v3)

### Key design decisions

- Push-to-talk: press-and-hold hotkey (onKeyDown starts recording, onKeyUp stops). DictationController handles a race where key-up arrives before recording actually starts
- WhisperEngine is an actor; the blocking `whisper_full` C call runs on a detached task via `withCheckedThrowingContinuation`
- LLMEngine is an actor; supports any OpenAI-compatible endpoint (local llama-server, Ollama, cloud APIs). No local LLM inference — purely HTTP client
- AudioRecorder creates a fresh `AVAudioEngine` per recording session and uses `AVAudioConverter` for sample rate conversion from hardware-native to 16kHz
- TextInserter uses `CGEvent` to simulate Cmd-V; requires Accessibility permission. Restores original pasteboard content after insertion
- PopupWindowController uses `NSPanel` with `.nonactivatingPanel` (no focus steal) and `.statusBar` level

### Tests

Only a stub test file exists at `Tests/TalkTypeTests/TalkTypeTests.swift` using the Swift Testing framework (`#expect(...)`).
