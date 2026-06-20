import Foundation

/// Emotion detected by Qwen-ASR. API values: happy, sad, angry, fearful, surprised, disgusted, neutral.
/// Used for UI empathy and LLM prompt context.
enum ASREmotion: String, Codable, Sendable, CaseIterable {
    case happy      = "happy"
    case neutral    = "neutral"
    case surprised  = "surprised"
    case sad        = "sad"
    case angry      = "angry"
    case fearful    = "fearful"
    case disgusted  = "disgusted"

    var isPositive: Bool {
        switch self {
        case .happy, .neutral, .surprised: return true
        case .sad, .angry, .fearful, .disgusted: return false
        }
    }

    var displayName: String {
        switch self {
        case .happy:     return "开心"
        case .neutral:   return "平静"
        case .surprised: return "惊喜"
        case .sad:       return "悲伤"
        case .angry:     return "生气"
        case .fearful:   return "紧张"
        case .disgusted: return "不悦"
        }
    }

    var friendlyMessage: String {
        switch self {
        case .happy:     return "😊 看起来你今天心情不错呢！"
        case .neutral:   return ""
        case .surprised: return "😮 有什么惊喜的事吗？"
        case .sad:       return "😔 听起来你有点难过，希望一切都好 🙏"
        case .angry:     return "😤 消消气，慢慢说～"
        case .fearful:   return "🫂 别紧张，慢慢说，我在听"
        case .disgusted: return "😣 看来不太愉快呢…"
        }
    }

    /// Whether this emotion should show the "帮我怼" roast button.
    var canRoast: Bool {
        switch self {
        case .angry, .disgusted: return true
        default: return false
        }
    }

    var promptHint: String {
        switch self {
        case .happy:     return "用户在说话时情绪为【开心】，请在优化时保留这种轻松积极的语调。"
        case .neutral:   return ""
        case .surprised: return "用户在说话时情绪为【惊喜】，请在优化时带有一点惊喜感。"
        case .sad:       return "用户在说话时情绪为【悲伤】，请在优化时保持温柔体贴的语气。"
        case .angry:     return "用户在说话时情绪为【生气】，请在优化时适当缓和语气但保留核心诉求。"
        case .fearful:   return "用户在说话时情绪为【紧张】，请在优化时使用安抚性的语气。"
        case .disgusted: return "用户在说话时情绪为【不悦】，请在优化时委婉表达但保留原意。"
        }
    }
}

/// Context passed to TextOptimizer for each optimization request.
struct OptimizationContext: Sendable {
    var emotion: ASREmotion?
    var toneStyle: ToneStyle
    var language: String
}

/// Protocol for text optimization steps. Each optimizer receives raw text
/// and context, returns the optimized result.
protocol TextOptimizer: Sendable {
    func optimize(_ text: String, context: OptimizationContext) async throws -> String
}

/// LLM-based text optimizer that uses any OpenAI-compatible endpoint.
/// Composes the system prompt from tone style + optional emotion context.
actor LLMOptimizer: TextOptimizer {
    private let engine: LLMEngine

    init(config: LLMEngine.Config) {
        self.engine = LLMEngine(config: config)
    }

    func updateConfig(_ newConfig: LLMEngine.Config) async {
        await engine.updateConfig(newConfig)
    }

    func optimize(_ text: String, context: OptimizationContext) async throws -> String {
        let systemPrompt = buildPrompt(tone: context.toneStyle, emotion: context.emotion)
        return try await engine.convert(text: text, systemPrompt: systemPrompt, maxTokens: 500)
    }

    private func buildPrompt(tone: ToneStyle, emotion: ASREmotion?) -> String {
        var prompt = tone.optimizationPrompt
        // 如果输入是问题，只润色问题表达，绝不回答
        prompt += "\n\n重要：如果用户输入的是一句提问或疑问句，请仅优化其措辞和表达方式，不要回答该问题本身。"
        if let emotion {
            prompt += "\n\n" + emotion.promptHint
        }
        return prompt
    }
}
