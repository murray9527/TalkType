# TalkType

macOS 菜单栏语音输入工具。按住快捷键说话，松开自动转文字。支持完全离线的本地 Whisper 识别，也可接入云端 ASR + LLM 做实时流式识别和语气润色。

---

## 功能

- 🎤 **按住说话，松开输入** — 全局热键，随时随地语音转文字
- 🏠 **本地离线运行** — Whisper 模型纯本地推理，无需联网
- 🌐 **实时流式识别** — 接入阿里云 Qwen-ASR，边说边出字
- ✨ **AI 语气润色** — 正式/简洁/口语/温柔/委婉/模棱两可，6 种风格一键转换
- 🔥 **怼人模式** — 帮你把话变得有攻击性
- 🎛️ **自定义远端服务** — 支持任意 OpenAI 兼容的 LLM API（DeepSeek、小米 MiMo、Ollama 等）
- ⌨️ **自由配置快捷键** — 全局热键随意改
- 📦 **开箱即用** — 下载 DMG 拖进 Applications 就能用

---

## 模型接入

TalkType 的核心理念是**模型无关**——你可以自由选择 ASR 识别引擎和 LLM 润色引擎，任意组合。

### 语音识别（ASR）

| 方案 | 模型 | 特点 |
|---|---|---|
| 本地离线 | Whisper Small / Medium / Large v3 | 纯本地推理，无需网络，中文 ★★★★★ |
| 预设远端 | 阿里云 Qwen-ASR（`qwen3-asr-flash-realtime`） | 服务端 VAD，实时流式出字，边说边显 |
| 自定义远端 | 任意 WebSocket ASR 服务 | 填入地址 + API Key + 模型名即可接入 |

### 语气润色（LLM）

| 方案 | 预置服务 | 模型名（可自定义） |
|---|---|---|
| 预设远端 | 阿里云 DashScope | `qwen-flash` / `qwen-plus` / `qwen-max` |
| 预设远端 | DeepSeek | `deepseek-v4-flash` / `deepseek-chat` |
| 预设远端 | 小米 MiMo | `mimo-v2-flash` |
| 自定义远端 | 任意 OpenAI 兼容接口 | 填入地址 + Key + 模型名 |
| 本地 LLM | Ollama / llama-server | `http://127.0.0.1:11434/v1` + 本地模型名 |

### 组合示例

```
本地 Whisper + 本地 Ollama     → 完全离线，数据不出本机
阿里云 ASR + 阿里云 LLM         → 全云端，实时流式 + 即时润色
阿里云 ASR + DeepSeek          → 流式识别 + 低价润色
自定义 ASR + 小米 MiMo         → 全自定义，数据走自己的服务
```

所有模型均可在设置中**实时切换**，填了 API Key 就能用，无需重启。

---

## 截图

<!-- TODO: 添加应用截图 GIF/PNG -->
<img width="560" height="572" alt="image" src="https://github.com/user-attachments/assets/25482f4e-da2e-4079-9331-481aab66bb59" />
<img width="1200" height="812" alt="image" src="https://github.com/user-attachments/assets/19b83554-a13a-4869-abad-2568967e5dbb" />

---

## 安装

### 下载 DMG（推荐）

从 [Releases](../../releases) 下载对应架构的 DMG：
<img width="600" height="193" alt="image" src="https://github.com/user-attachments/assets/25d09feb-11fd-45ec-a94a-4d88266f508e" />

| 架构 | 文件 |
|---|---|
| Apple Silicon (M1–M4) | `TalkType-arm64.dmg` |
| Intel | `TalkType-x86_64.dmg` |

双击挂载，把 TalkType 拖到 Applications 即可。

首次启动需要授予**麦克风**和**辅助功能**权限（系统设置 → 隐私与安全性）。

### 从源码构建

```bash
git clone https://github.com/murray9527/TalkType.git
cd TalkType
swift build -c release
```

要求：macOS 13+，Swift 6.0，Xcode 15+

---

## 使用

1. 打开设置 → 模型设置，选择 ASR 模型并填入 API Key（或下载本地模型），点击「启用」
2. 如需语气润色，开启「一般设置」→「文本优化」，选择语气风格，并配置 LLM 模型
3. 按住快捷键说话，松开自动转文字
4. 识别完成后弹出编辑面板：

| 快捷键 | 操作 |
|---|---|
| `⌘↑` | 插入原始识别文本 |
| `⌘↓` | 插入优化后文本 |
| `Esc` | 取消本次输入 |

> 本地 Whisper 模型不支持实时流式，松开后才开始转写。

---

## 架构

```
按热键 → 录音 → ASR 识别 → 文本清洗 → (可选) LLM 润色 → 模拟粘贴
```

| 模块 | 文件 | 职责 |
|---|---|---|
| 录音 | `Audio/AudioRecorder.swift` | AVAudioEngine 采集，转 16kHz 单声道 |
| 本地识别 | `ASR/WhisperEngine.swift` | whisper.cpp actor，离线转写 |
| 远端识别 | `ASR/RemoteASREngine.swift` | WebSocket 流式 ASR，服务端 VAD |
| 语气润色 | `LLM/LLMEngine.swift` | OpenAI 兼容 HTTP 客户端 |
| 文本插入 | `UI/TextInserter.swift` | CGEvent 模拟 Cmd-V，还原剪贴板 |
| 弹窗 | `UI/DictationPopupView.swift` | SwiftUI 三阶段弹出面板 |
| 调度 | `App/DictationController.swift` | MainActor 单例，串联全流程 |

---

## 技术要点

- **Swift 6** 严格并发。WhisperEngine / RemoteASREngine / LLMEngine 均为 actor
- 快捷键基于 Carbon `EventHotKey`，push-to-talk 模型
- 每次录音创建新的 `AVAudioEngine` 实例，`AVAudioConverter` 转采样率
- 弹窗为 `NSPanel` + `.nonactivatingPanel` + `.statusBar` level，不抢焦点
- 设置用 `@Published` + `didSet` 同步 `UserDefaults`，编辑即生效
- 远端服务配置持久化到 SQLite（GRDB），预置阿里云/DeepSeek/小米

---

## 路线图

| 功能 | 状态 |
|---|---|
| 本地 Whisper 转写 | ✅ |
| 远端实时流式 ASR | ✅ |
| LLM 语气润色（6 种风格） | ✅ |
| 怼人模式 | ✅ |
| 可编辑弹出面板 | ✅ |
| 热词 / 语境偏置 | ✅ |
| 情感感知 | ✅ |
| 引导向导 | ✅ |
| 模型下载管理 | ✅ |
| DMG 分架构打包 | ✅ |
| 官网 | 🔜 |
| 官方订阅服务 | 🔜 |

---

## 许可

[MIT](LICENSE)
