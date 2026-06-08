import Foundation

// Rule-based post-processing applied to every Whisper transcription.
// Produces "basic text" — clean, usable output without LLM involvement.
struct TextPostProcessor {

    // Ordered list of filler patterns to strip (Chinese oral fillers).
    private static let fillerPatterns: [String] = [
        "然后就是", "然后嘛", "就是说", "就是嘛", "就是那个",
        "那个那个", "那个嘛", "这个这个", "这个嘛",
        "你懂我意思吗", "你明白吗", "你知道吗", "对吧", "是吧", "嗯哼",
        "嗯嗯", "嗯", "啊", "哦", "呢", "吧", "嘛",
    ]

    // Repeated word pattern: matches "XYZXYZ" consecutive duplicate words (2-4 chars).
    private static let repeatedWordRegex = try! NSRegularExpression(
        pattern: "([\\u4e00-\\u9fa5a-zA-Z]{1,4})\\1+",
        options: []
    )

    func process(_ raw: String) -> String {
        var text = raw

        // 1. Remove filler phrases (longest first to avoid partial matches)
        let sorted = Self.fillerPatterns.sorted { $0.count > $1.count }
        for filler in sorted {
            text = text.replacingOccurrences(of: filler, with: "")
        }

        // 2. Collapse repeated words
        let range = NSRange(text.startIndex..., in: text)
        text = Self.repeatedWordRegex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: "$1"
        )

        // 3. Normalize whitespace
        text = text.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // 4. Add trailing punctuation if missing
        text = addTrailingPunctuation(text)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addTrailingPunctuation(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let last = text.last!
        let alreadyPunctuated = "。？！.?!…".contains(last)
        guard !alreadyPunctuated else { return text }

        // Simple heuristic: if ends with question word, add ？
        let questionWords = ["吗", "嘛", "呢", "吧", "什么", "哪", "谁", "怎么", "为什么", "几"]
        if questionWords.contains(where: { text.hasSuffix($0) }) {
            return text + "？"
        }
        return text + "。"
    }
}
