import Foundation

// LLM client for any OpenAI-compatible chat completions HTTP endpoint.
// Supports AliCloud DashScope, DeepSeek, Xiaomi MiMo, Ollama, local llama-server, etc.
actor LLMEngine {

    struct Config: Sendable {
        var baseURL: String
        var apiKey: String
        var model: String
        var maxTokens: Int
        var temperature: Double

        static func from(service: RemoteService) -> Config {
            Config(
                baseURL: service.baseURL,
                apiKey: service.apiKey,
                model: service.modelName,
                maxTokens: 300,
                temperature: 0.3
            )
        }
    }

    private var config: Config
    private let session: URLSession

    init(config: Config = Config(baseURL: "http://127.0.0.1:8080", apiKey: "", model: "", maxTokens: 300, temperature: 0.3)) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: sessionConfig)
    }

    deinit {
        session.invalidateAndCancel()
    }

    func updateConfig(_ newConfig: Config) {
        config = newConfig
    }

    // MARK: - URL construction

    // OpenAI-compatible convention:
    //   baseURL without /v1 suffix → append /v1/chat/completions
    //   baseURL with    /v1 suffix → strip it first, then append (avoids double /v1)
    private func endpoint(_ path: String) -> URL? {
        let base = config.baseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        let baseWithoutV1 = base.hasSuffix("/v1") ? String(base.dropLast(3)) : base
        return URL(string: baseWithoutV1 + "/v1" + path)
    }

    // MARK: - Inference

    func convert(text: String, systemPrompt: String, maxTokens: Int? = nil) async throws -> String {
        guard let url = endpoint("/chat/completions") else {
            throw LLMError.invalidURL
        }

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
            throw LLMError.httpError(status)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Health check

    func checkAvailability() async -> Bool {
        guard let url = endpoint("/models") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        if !config.apiKey.isEmpty {
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        guard let (_, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    enum LLMError: Error {
        case httpError(Int)
        case invalidResponse
        case invalidURL
    }
}
