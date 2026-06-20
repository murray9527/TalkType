import Testing
@testable import TalkType

// MARK: - ToneStyle

@Test func allStylesHaveSystemPrompts() {
    let styles: [ToneStyle] = [.formal, .professional, .gentle, .ambiguous, .none]
    for style in styles {
        #expect(!style.systemPrompt.isEmpty, "\(style.rawValue) should have a non-empty system prompt")
    }
}

@Test func allStylesHaveDisplayNames() {
    for style in ToneStyle.allCases {
        #expect(!style.displayName.isEmpty)
    }
}

@Test func promptsIncludeCleaningInstructions() {
    let styles: [ToneStyle] = [.formal, .professional, .gentle, .ambiguous, .none]
    for style in styles {
        let prompt = style.systemPrompt
        #expect(prompt.contains("优化"), "\(style.rawValue) should contain optimization instruction")
        #expect(prompt.contains("标点"), "\(style.rawValue) should mention punctuation")
        #expect(prompt.contains("结果"), "\(style.rawValue) should instruct to output only the result")
        #expect(prompt.contains("不要解释"), "\(style.rawValue) should say '只输出优化后的结果，不要解释'")
    }
}
