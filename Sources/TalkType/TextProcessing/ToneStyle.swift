import Foundation
import SwiftUI

// Tone styles available for LLM-based conversion.
// Ordered by estimated usage frequency — most common first.
enum ToneStyle: String, CaseIterable, Identifiable, Codable {
    case none      = "不调整"
    case formal    = "正式"
    case concise   = "简洁"
    case polite    = "礼貌"
    case oral      = "口语化"
    case gentle    = "委婉"
    case ambiguous = "暧昧"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:      return "不调整"
        case .formal:    return "正式"
        case .concise:   return "简洁"
        case .polite:    return "礼貌"
        case .oral:      return "口语化"
        case .gentle:    return "委婉"
        case .ambiguous: return "暧昧"
        }
    }

    // Legacy prompt alias — kept for backward compatibility.
    var systemPrompt: String { optimizationPrompt }

    /// LLM prompt for text optimization.
    var optimizationPrompt: String {
        switch self {
        case .none:
            return ""
        case .formal:
            return "将以下语音识别文本优化为正式书面语，适合邮件、公文或报告场合。请去除口语填充词（嗯、啊、那个、就是等），使用准确规范的用词，调整语气使其正式得体，规范标点，保持原意。只输出优化后的结果，不要解释。"
        case .concise:
            return "将以下语音识别文本精简为简洁直接的表达，去除冗余和重复信息，保留核心内容，用最少的字说清楚。请去除口语填充词，规范标点。只输出优化后的结果，不要解释。"
        case .polite:
            return "将以下语音识别文本优化为礼貌客气的表达方式，适合求人办事、客服沟通或正式社交场合。请去除口语填充词，使用敬语和委婉措辞，保持尊重得体的语气，规范标点。只输出优化后的结果，不要解释。"
        case .oral:
            return "将以下语音识别文本转化为自然的口语表达，适合日常聊天、微信语音或非正式交流。请去除口语填充词（嗯、啊、那个、就是等），保留自然的语调和表达习惯，避免书面化和生硬措辞，规范标点。只输出优化后的结果，不要解释。"
        case .gentle:
            return "将以下语音识别文本优化为委婉、温和的表达方式，适合提建议、拒绝或反馈场合。请去除口语填充词，简化冗余表达，保留核心意思但语气柔和，规范标点。只输出优化后的结果，不要解释。"
        case .ambiguous:
            return "将以下语音识别文本优化为带有一定情感模糊性的社交表达，适合聊天场合。请去除口语填充词，简化冗余表达，规范标点，保留一定暧昧感。只输出优化后的结果，不要解释。"
        }
    }
}
