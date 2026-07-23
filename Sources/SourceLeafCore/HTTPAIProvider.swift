import Foundation

public final class HTTPAIProvider: AIProvider, @unchecked Sendable {
    public let displayName: String
    private let profile: ProviderProfile
    private let apiKey: String?
    private let session: URLSession

    public init(profile: ProviderProfile, apiKey: String?, session: URLSession = .shared) {
        self.profile = profile
        self.apiKey = apiKey
        self.session = session
        self.displayName = profile.name
    }

    public func generateProposal(for request: AIRequest) async throws -> AIProposal {
        try await generateProposal(for: request, onEvent: { _ in })
    }

    public func generateProposal(
        for request: AIRequest,
        onEvent: @escaping @Sendable (AIProviderEvent) -> Void
    ) async throws -> AIProposal {
        onEvent(.requestStarted)
        let text = try await perform(
            prompt: AIEditPromptBuilder.build(request),
            systemPrompt: request.systemPrompt
        )
        onEvent(.responseStarted)
        if request.targets.isEmpty { onEvent(.textDelta(text)) }
        if request.targets.isEmpty {
            return AIProposal(summary: text.trimmingCharacters(in: .whitespacesAndNewlines), replacements: [], providerName: displayName)
        }
        return try AIProposalCodec.decode(text, providerName: displayName)
    }

    public func healthCheck() async throws -> String {
        try AIProviderHealthCheck.validated(
            try await perform(prompt: AIProviderHealthCheck.prompt, systemPrompt: "")
        )
    }

    private func perform(prompt: String, systemPrompt: String) async throws -> String {
        let urlRequest = try makeRequest(prompt: prompt, systemPrompt: systemPrompt)
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse("No HTTP response was returned.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIProviderError.requestFailed(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        return try extractText(from: data)
    }

    func makeRequest(prompt: String, systemPrompt: String = "") throws -> URLRequest {
        let endpoint = try endpointURL()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in profile.headers { request.setValue(value, forHTTPHeaderField: name) }

        let body: Any
        switch profile.kind {
        case .openAI:
            guard let apiKey, !apiKey.isEmpty else { throw AIProviderError.missingCredential }
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            var openAIBody: [String: Any] = ["model": profile.model, "input": prompt]
            if !systemPrompt.isEmpty { openAIBody["instructions"] = systemPrompt }
            if let effort = profile.reasoningEffort {
                openAIBody["reasoning"] = ["effort": effort.rawValue]
            }
            body = openAIBody
        case .openAICompatible:
            if let apiKey, !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            var messages: [[String: String]] = []
            if !systemPrompt.isEmpty { messages.append(["role": "system", "content": systemPrompt]) }
            messages.append(["role": "user", "content": prompt])
            var compatibleBody: [String: Any] = [
                "model": profile.model,
                "messages": messages,
                "temperature": 0
            ]
            if let effort = profile.reasoningEffort {
                compatibleBody["reasoning_effort"] = effort.rawValue
            }
            body = compatibleBody
        case .lmStudio:
            if let apiKey, !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            var messages: [[String: String]] = []
            if !systemPrompt.isEmpty { messages.append(["role": "system", "content": systemPrompt]) }
            messages.append(["role": "user", "content": prompt])
            body = [
                "model": profile.model,
                "messages": messages,
                "temperature": 0
            ] as [String: Any]
        case .anthropic:
            guard let apiKey, !apiKey.isEmpty else { throw AIProviderError.missingCredential }
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var anthropicBody: [String: Any] = [
                "model": profile.model,
                "max_tokens": 8192,
                "messages": [["role": "user", "content": prompt]]
            ]
            if !systemPrompt.isEmpty { anthropicBody["system"] = systemPrompt }
            body = anthropicBody
        case .gemini:
            guard let apiKey, !apiKey.isEmpty else { throw AIProviderError.missingCredential }
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
            let existingItems = components?.queryItems ?? []
            components?.queryItems = existingItems + [URLQueryItem(name: "key", value: apiKey)]
            guard let keyedURL = components?.url else { throw AIProviderError.invalidResponse("Invalid Gemini endpoint.") }
            request.url = keyedURL
            var geminiBody: [String: Any] = [
                "contents": [["parts": [["text": prompt]]]]
            ]
            if !systemPrompt.isEmpty {
                geminiBody["systemInstruction"] = ["parts": [["text": systemPrompt]]]
            }
            body = geminiBody
        case .ollama:
            var messages: [[String: String]] = []
            if !systemPrompt.isEmpty { messages.append(["role": "system", "content": systemPrompt]) }
            messages.append(["role": "user", "content": prompt])
            body = [
                "model": profile.model,
                "stream": false,
                "messages": messages
            ] as [String: Any]
        default:
            throw AIProviderError.invalidResponse("This profile is not an HTTP provider.")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func endpointURL() throws -> URL {
        let base: String
        switch profile.kind {
        case .openAI:
            base = profile.baseURL ?? "https://api.openai.com/v1/responses"
        case .anthropic:
            base = profile.baseURL ?? "https://api.anthropic.com/v1/messages"
        case .gemini:
            let model = profile.model.isEmpty ? "gemini-2.5-pro" : profile.model
            base = profile.baseURL ?? "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        case .ollama:
            base = profile.baseURL ?? "http://127.0.0.1:11434/api/chat"
        case .lmStudio:
            base = profile.baseURL ?? "http://127.0.0.1:1234/v1/chat/completions"
        case .openAICompatible:
            guard let configured = profile.baseURL, !configured.isEmpty else {
                throw AIProviderError.invalidResponse("Configure a Base URL for this provider.")
            }
            base = configured.hasSuffix("/chat/completions") ? configured : configured.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
        default:
            throw AIProviderError.invalidResponse("This profile does not use HTTP.")
        }
        guard let url = URL(string: base) else { throw AIProviderError.invalidResponse("The provider URL is invalid.") }
        return url
    }

    private func extractText(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse("The response is not a JSON object.")
        }

        if profile.kind == .openAI {
            if let outputText = root["output_text"] as? String { return outputText }
            if let output = root["output"] as? [[String: Any]] {
                for item in output {
                    if let content = item["content"] as? [[String: Any]],
                       let text = content.compactMap({ $0["text"] as? String }).last {
                        return text
                    }
                }
            }
        }
        if profile.kind == .anthropic,
           let content = root["content"] as? [[String: Any]],
           let text = content.compactMap({ $0["text"] as? String }).last {
            return text
        }
        if profile.kind == .gemini,
           let candidates = root["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let text = parts.compactMap({ $0["text"] as? String }).last {
            return text
        }
        if profile.kind == .ollama,
           let message = root["message"] as? [String: Any],
           let text = message["content"] as? String {
            return text
        }
        if let choices = root["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let text = message["content"] as? String {
            return text
        }
        throw AIProviderError.invalidResponse("No assistant text was found.")
    }
}
