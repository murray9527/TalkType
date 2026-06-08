# TalkType

本地隐私语音输入法。100% 离线运行，音频不离开设备。

## 产品功能

- **基础能力**：语音转文字 + 去语气助词 + 标点修正（规则引擎，无 LLM）
- **语气转换**（可选）：基础文本 → 正式 / 专业 / 委婉 / 暧昧（本地 LLM）
- **交互**：Push-to-Talk 热键，识别后弹出二选一浮窗

## 文档

- [`docs/PRODUCT.md`](docs/PRODUCT.md) — 完整产品设计方案

## 项目结构

```
Sources/TalkType/
├── App/
│   ├── TalkTypeApp.swift        # @main SwiftUI App
│   ├── AppDelegate.swift        # NSApp 配置、菜单栏、状态图标
│   ├── HotkeyManager.swift      # 全局 Carbon 热键监听
│   └── DictationController.swift # 听写流水线编排
├── Audio/
│   └── AudioRecorder.swift      # AVAudioEngine 采集 16kHz PCM
├── ASR/
│   └── WhisperEngine.swift      # whisper.cpp Swift 封装
├── TextProcessing/
│   ├── TextPostProcessor.swift  # 规则引擎：去语气助词、标点补全
│   └── ToneStyle.swift          # 语气风格枚举 + System Prompt
├── UI/
│   ├── ResultPopupView.swift    # 结果浮窗（SwiftUI）
│   ├── PopupWindowController.swift # NSPanel 浮窗管理
│   ├── PreferencesView.swift    # 偏好设置界面
│   └── TextInserter.swift       # Pasteboard 文字插入
└── Models/
    └── AppSettings.swift        # UserDefaults 设置持久化
```

## 开发环境

- macOS 13+
- Xcode 15+ / Swift 6
- 依赖：whisper.cpp（via whisper.spm）、GRDB.swift

## 快速开始

```bash
# 1. 下载 Whisper 模型（约 480MB）
mkdir -p ~/Library/Application\ Support/TalkType/models
curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin \
     -o ~/Library/Application\ Support/TalkType/models/ggml-small.bin

# 2. 构建运行
swift run
```

## 路线图

| 阶段 | 内容 | 状态 |
|---|---|---|
| Week 1-2 | ASR 核心（whisper.cpp + 音频采集 + 规则引擎）| 🔄 进行中 |
| Week 3-4 | macOS 应用骨架（菜单栏 + 热键 + 浮窗 + 文字插入）| ⏳ 待开始 |
| Week 5-6 | LLM 集成（llama.cpp + Qwen + 语气转换 Prompt）| ⏳ 待开始 |
| Week 7-8 | 模型管理 + 偏好设置 + Onboarding | ⏳ 待开始 |
