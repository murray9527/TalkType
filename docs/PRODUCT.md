# TalkType 产品设计方案

## 产品定位

macOS 菜单栏语音输入工具。按住快捷键说话，松开自动转文字并插入。核心差异：
- **模型无关**：ASR 和 LLM 均可自由替换，本地/远端/自定义任意组合
- **隐私优先**：纯本地 Whisper 模式下音频不出本机
- **实时流式**：远端模式下边说边出字

---

## 一、核心交互流程

```
按住 Option + 空格 → 录音 → 松开 → ASR 识别 → 文本清洗 → (可选) LLM 润色 → 弹窗确认 → 插入
```

### 弹窗交互

识别完成后弹出编辑面板，用户可编辑原始文本后再插入：

| 操作 | 快捷键 | 说明 |
|---|---|---|
| 插入原始文本 | `⌘↑` | 不经过润色，直接插入识别+清洗后的文本 |
| 插入优化文本 | `⌘↓` | 插入 LLM 润色后的文本 |
| 取消 | `Esc` | 丢弃本次识别结果 |

弹窗内有两个编辑区：上为原始识别文本（可编辑），下为润色结果（异步加载）。

---

## 二、模型接入策略

### 语音识别（ASR）

| 类型 | 实现 | 特点 |
|---|---|---|
| 本地 Whisper | whisper.cpp，Small / Medium / Large v3 | 纯本地推理，非实时（录音完成→转写） |
| 远端预设 | 阿里云 Qwen-ASR，WebSocket 协议 | 服务端 VAD，实时流式出字 |
| 远端自定义 | 任意 WebSocket ASR 服务 | 填地址+Key+模型名即可 |

### 语气润色（LLM）

| 类型 | 预置服务 | 协议 |
|---|---|---|
| 远端预设 | 阿里云 DashScope / DeepSeek / 小米 MiMo | OpenAI 兼容 HTTP API |
| 远端自定义 | 任意 OpenAI 兼容接口 | 填地址+Key+模型名 |
| 本地 LLM | Ollama / llama-server | `http://127.0.0.1:11434/v1` |

所有模型可在设置中实时切换，无需重启。

---

## 三、文本处理流水线

```
原始识别文本
    │
    ▼
规则清洗（自动，无需用户操作）
    ├─ 去语气助词："嗯""那个""就是"等
    ├─ 标点补全：句尾加句号
    └─ 重复词去重："这个这个" → "这个"
    │
    ▼
基础文本 ──→ (可选) LLM 语气转换 ──→ 风格文本
```

### 语气风格（6 种）

正式 / 简洁 / 口语 / 温柔 / 委婉 / 模棱两可

### 高级功能

- **怼人模式**：激进语气，用于反击/调侃
- **情感感知**：从 ASR 结果中检测情绪，影响润色 Prompt
- **热词偏置**：提升特定人名、专业术语的识别准确率

---

## 四、技术栈

| 层 | 技术 |
|---|---|
| UI | SwiftUI，菜单栏 App（无 Dock 图标） |
| 本地 ASR | whisper.cpp（Swift Package，actor 封装） |
| 远端 ASR | URLSession WebSocket，服务端 VAD |
| LLM | URLSession HTTP，OpenAI 兼容 API |
| 音频采集 | AVAudioEngine，AVAudioConverter 转 16kHz 单声道 |
| 全局热键 | Carbon EventHotKey（push-to-talk） |
| 文字插入 | CGEvent 模拟 Cmd-V + Pasteboard 还原 |
| 弹窗 | NSPanel（.nonactivatingPanel，不抢焦点） |
| 本地存储 | SQLite（GRDB.swift），UserDefaults |
| 模型下载 | URLSessionDownloadDelegate，hf-mirror.com 镜像 |

---

## 五、设置页架构

### 一般设置
- 全局热键录制
- 热词配置
- 文本优化开关（影响使用中的行为，不影响设置内容可见性）

### 模型设置
- 订阅状态提示（暂未开放）
- ASR：语言选择 / 本地 vs 远端模型 / 预设服务 + 自定义接入
- LLM：语气风格 / 预设服务 + 自定义接入 / 模型名可自由编辑

所有设置编辑即生效，无需手动保存。

---

## 六、已实现 vs 原计划

| 功能 | 状态 | 说明 |
|---|---|---|
| 本地 Whisper 转写 | ✅ | whisper.cpp actor，三档模型 |
| 远端实时流式 ASR | ✅ | Qwen-ASR WebSocket |
| 规则清洗引擎 | ✅ | 去语气词 + 标点 + 去重 |
| LLM 语气润色 | ✅ | 6 种风格，OpenAI 兼容 |
| 怼人模式 | ✅ | 激进 Prompt |
| 情感感知 | ✅ | ASR 结果中提取情绪 |
| 热词偏置 | ✅ | 提升专有名词识别率 |
| 可编辑弹窗 | ✅ | 双编辑区 + 快捷键 |
| 引导向导 | ✅ | 4 步 Onboarding |
| 模型下载管理 | ✅ | URLSession + 断点续传 |
| DMG 分架构打包 | ✅ | arm64 + x86_64 |
| 本地 LLM 推理 | ❌ | 改为远端 API 方案 |
| Silero VAD | ❌ | 依赖服务端 VAD |
| 官网 | 🔜 | |
| 官方订阅 | 🔜 | |
