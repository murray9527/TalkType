import Foundation

// LLM client that talks to any OpenAI-compatible HTTP endpoint.
// Supports:
//   - Local llama-server: http://127.0.0.1:8080 (llama.cpp built-in server)
//   - Ollama: http://127.0.0.1:11434/v1
//   - Any OpenAI-compatible API (DeepSeek, Groq, etc.) — user supplies base URL + key
//
// When baseURL is a local address (127.0.0.1 / localhost), no API key is required.
actor LlamaEngine {

    // MARK: - Configuration

    struct Config: Sendable {
        var baseURL: String    // e.g. "http://127.0.0.1:8080"
        var apiKey: String     // empty = no auth header
        var model: String      // e.g. "qwen2.5-1.5b-instruct" or left empty for llama-server default
        var maxTokens: Int
        var temperature: Double

        static let localLlamaServer = Config(
            baseURL: "http://127.0.0.1:8080",
            apiKey: "",
            model: "",
            maxTokens: 300,
            temperature: 0.3
        )

        static let ollama = Config(
            baseURL: "http://127.0.0.1:11434/v1",
            apiKey: "ollama",
            model: "qwen2.5:1.5b",
            maxTokens: 300,
            temperature: 0.3
        )
    }

    private var config: Config
    private let session: URLSession

    var isLoaded: Bool {
        // For HTTP mode, "loaded" means the endpoint is reachable.
        // We do a lazy check — return true and let inference fail gracefully if not.
        true
    }

    init(config: Config = .localLlamaServer) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: sessionConfig)
    }

    func updateConfig(_ newConfig: Config) {
        config = newConfig
    }

    // MARK: - Inference

    func convert(text: String, systemPrompt: String, maxTokens: Int? = nil) async throws -> String {
        let url = URL(string: config.baseURL.trimmingCharacters(in: .init(charactersIn: "/")) + "/v1/chat/completions")!

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": maxTokens ?? config.maxTokens,
            "temperature": config.temperature,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LlamaError.httpError(status)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LlamaError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Health check

    func checkAvailability() async -> Bool {
        guard let url = URL(string: config.baseURL + "/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        return (try? await session.data(for: req)) != nil
    }

    enum LlamaError: Error {
        case httpError(Int)
        case invalidResponse
    }
}
