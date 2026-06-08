import Foundation

// Tone styles available for LLM-based conversion.
enum ToneStyle: String, CaseIterable, Identifiable, Codable {
    case formal    = "正式"
    case professional = "专业"
    case gentle    = "委婉"
    case ambiguous = "暧昧"
    case none      = "无"

    var id: String { rawValue }

    // System prompt fragment describing the desired transformation.
    var systemPrompt: String {
        switch self {
        case .formal:
            return "将以下口语文本改写为正式书面语，适合邮件、公文或报告场合。保持原意，去除口语化表达，使用规范标点。只输出改写后的文本，不要解释。"
        case .professional:
            return "将以下口语文本改写为专业技术风格，适合技术文档或学术写作。使用准确术语，结构清晰。只输出改写后的文本，不要解释。"
        case .gentle:
            return "将以下文本改写为委婉、温和的表达方式，适合提建议、拒绝或反馈场合。保留核心意思但语气柔和。只输出改写后的文本，不要解释。"
        case .ambiguous:
            return "将以下文本改写为带有一定情感模糊性的社交表达，适合聊天场合，保留一定暧昧感。只输出改写后的文本，不要解释。"
        case .none:
            return ""
        }
    }
}
