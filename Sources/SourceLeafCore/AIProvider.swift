import Foundation

public struct AIRequest: Sendable {
    public var instruction: String
    public var targets: [SourceTarget]
    public var context: [String: String]
    public var projectRoot: URL

    public init(
        instruction: String,
        targets: [SourceTarget],
        context: [String: String],
        projectRoot: URL
    ) {
        self.instruction = instruction
        self.targets = targets
        self.context = context
        self.projectRoot = projectRoot
    }
}

public protocol AIProvider: Sendable {
    var displayName: String { get }
    func generateProposal(for request: AIRequest) async throws -> AIProposal
    func healthCheck() async throws -> String
}

public enum AIProviderHealthCheck {
    public static let prompt = "Reply with exactly hello and nothing else."

    public static func validated(_ response: String) throws -> String {
        let normalized = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized == "hello" else {
            throw AIProviderError.invalidResponse("Health check expected hello but received: \(response.prefix(120))")
        }
        return normalized
    }
}

public enum AIProviderError: Error, LocalizedError {
    case executableNotFound(String)
    case emptyResponse
    case invalidResponse(String)
    case requestFailed(Int, String)
    case missingCredential

    public var errorDescription: String? {
        switch self {
        case let .executableNotFound(name): "Could not find the \(name) executable."
        case .emptyResponse: "The provider returned an empty response."
        case let .invalidResponse(message): "The provider response was not a valid SourceLeaf proposal: \(message)"
        case let .requestFailed(status, message): "The provider request failed (HTTP \(status)): \(message)"
        case .missingCredential: "This provider requires an API key."
        }
    }
}

public enum AIProposalCodec {
    private struct RawProposal: Decodable {
        struct RawReplacement: Decodable {
            var targetID: UUID
            var replacement: String
            var explanation: String?

            enum CodingKeys: String, CodingKey {
                case targetID = "target_id"
                case replacement
                case explanation
            }
        }

        var summary: String
        var replacements: [RawReplacement]
    }

    public static func decode(_ response: String, providerName: String) throws -> AIProposal {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIProviderError.emptyResponse }
        let json: String
        if let first = trimmed.firstIndex(of: "{"), let last = trimmed.lastIndex(of: "}"), first <= last {
            json = String(trimmed[first...last])
        } else {
            throw AIProviderError.invalidResponse("No JSON object was found.")
        }

        do {
            let raw = try JSONDecoder().decode(RawProposal.self, from: Data(json.utf8))
            return AIProposal(
                summary: raw.summary,
                replacements: raw.replacements.map {
                    ProposedReplacement(targetID: $0.targetID, replacement: $0.replacement, explanation: $0.explanation ?? "")
                },
                providerName: providerName
            )
        } catch {
            throw AIProviderError.invalidResponse(error.localizedDescription)
        }
    }
}

public enum AIEditPromptBuilder {
    public static func build(_ request: AIRequest) -> String {
        if request.targets.isEmpty {
            return AIChatPromptBuilder.build(request)
        }
        let targetBlocks = request.targets.map { target in
            """
            <target id="\(target.id.uuidString)" file="\(target.relativePath)" lines="\(target.startLine)-\(target.endLine)">
            \(target.originalText)
            </target>
            """
        }.joined(separator: "\n\n")
        let contextBlocks = request.context.sorted { $0.key < $1.key }.map { name, value in
            """
            <context name="\(name)">
            \(value)
            </context>
            """
        }.joined(separator: "\n\n")

        return """
        You are the revision engine inside SourceLeaf, a LaTeX editor.

        User instruction:
        \(request.instruction)

        Writable targets follow. You may replace only these exact targets. Context is read-only.
        \(targetBlocks)

        Read-only context:
        \(contextBlocks)

        Preserve LaTeX commands, citations, labels, references, equations, and factual claims unless the user explicitly asks to change them. Do not wrap replacements in Markdown fences.

        Return exactly one JSON object with this shape:
        {
          "summary": "brief explanation",
          "replacements": [
            {
              "target_id": "UUID copied exactly from a target",
              "replacement": "complete replacement text for only that target",
              "explanation": "what changed"
            }
          ]
        }

        Include one replacement per target that should change. Never invent target IDs. If the request is unsafe or ambiguous, return an empty replacements array and explain why in summary.
        """
    }
}

public enum AIChatPromptBuilder {
    public static func build(_ request: AIRequest) -> String {
        let contextBlocks = request.context.sorted { $0.key < $1.key }.map { name, value in
            "<context name=\"\(name)\">\n\(value)\n</context>"
        }.joined(separator: "\n\n")
        return """
        You are the conversation assistant inside SourceLeaf, a LaTeX editor.
        Answer the user's request directly in plain text. Do not return JSON.

        User message:
        \(request.instruction)

        Optional read-only context:
        \(contextBlocks)
        """
    }
}

public final class CodexCLIProvider: AIProvider, @unchecked Sendable {
    public let displayName: String
    private let executableURL: URL
    private let runner: ProcessRunner
    private let profile: ProviderProfile

    public init(
        profile: ProviderProfile = .localCodex,
        executableURL: URL? = nil,
        runner: ProcessRunner = ProcessRunner()
    ) throws {
        guard let executableURL = executableURL ?? ExecutableLocator.find("codex") else {
            throw AIProviderError.executableNotFound("codex")
        }
        self.executableURL = executableURL
        self.runner = runner
        self.profile = profile
        displayName = profile.name
    }

    public func generateProposal(for request: AIRequest) async throws -> AIProposal {
        let prompt = AIEditPromptBuilder.build(request)
        let sandboxDirectory = try Self.sandboxDirectory(
            key: String(SourceTargetService.hash(request.projectRoot.standardizedFileURL.path).prefix(16))
        )
        try FileManager.default.createDirectory(at: sandboxDirectory, withIntermediateDirectories: true)
        let output = try await runner.run(
            executableURL: executableURL,
            arguments: Self.invocationArguments(for: profile),
            currentDirectoryURL: sandboxDirectory,
            input: Data(prompt.utf8)
        )
        guard output.exitCode == 0 else { throw ProcessRunnerError.nonZeroExit(output) }
        let message = Self.lastAgentMessage(in: output.standardOutput) ?? output.standardOutput
        if request.targets.isEmpty {
            return AIProposal(summary: message.trimmingCharacters(in: .whitespacesAndNewlines), replacements: [], providerName: displayName)
        }
        return try AIProposalCodec.decode(message, providerName: displayName)
    }

    public func healthCheck() async throws -> String {
        let sandboxDirectory = try Self.sandboxDirectory(key: "Health")
        try FileManager.default.createDirectory(at: sandboxDirectory, withIntermediateDirectories: true)
        let output = try await runner.run(
            executableURL: executableURL,
            arguments: Self.invocationArguments(for: profile),
            currentDirectoryURL: sandboxDirectory,
            input: Data(AIProviderHealthCheck.prompt.utf8)
        )
        guard output.exitCode == 0 else { throw ProcessRunnerError.nonZeroExit(output) }
        let message = Self.lastAgentMessage(in: output.standardOutput) ?? output.standardOutput
        return try AIProviderHealthCheck.validated(message)
    }

    private static func sandboxDirectory(key: String) throws -> URL {
        try ApplicationDirectories.supportDirectory()
            .appendingPathComponent("ProviderWorkspaces", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
    }

    public static func invocationArguments(for profile: ProviderProfile) -> [String] {
        var arguments = ["exec"]
        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            arguments += ["--model", model]
        }
        if let effort = profile.reasoningEffort {
            arguments += ["--config", "model_reasoning_effort=\"\(effort.rawValue)\""]
        }
        arguments += [
            "--json", "--color", "never", "--ephemeral",
            "--sandbox", "read-only", "--skip-git-repo-check", "-"
        ]
        return arguments
    }

    public static func lastAgentMessage(in jsonLines: String) -> String? {
        var latest: String?
        for line in jsonLines.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let item = object["item"] as? [String: Any],
               let type = item["type"] as? String,
               type == "agent_message",
               let text = item["text"] as? String {
                latest = text
            } else if let type = object["type"] as? String,
                      type == "agent_message",
                      let text = object["text"] as? String {
                latest = text
            }
        }
        return latest
    }
}

public final class CodeBuddyCLIProvider: AIProvider, @unchecked Sendable {
    public let displayName: String
    private let executableURL: URL
    private let runner: ProcessRunner
    private let profile: ProviderProfile

    public init(
        profile: ProviderProfile = .localCodeBuddy,
        executableURL: URL? = nil,
        runner: ProcessRunner = ProcessRunner()
    ) throws {
        guard let executableURL = executableURL
            ?? ExecutableLocator.find("codebuddy")
            ?? ExecutableLocator.find("cbc") else {
            throw AIProviderError.executableNotFound("codebuddy")
        }
        self.executableURL = executableURL
        self.runner = runner
        self.profile = profile
        displayName = profile.name
    }

    public func generateProposal(for request: AIRequest) async throws -> AIProposal {
        let text = try await run(prompt: AIEditPromptBuilder.build(request), workspaceKey: String(
            SourceTargetService.hash(request.projectRoot.standardizedFileURL.path).prefix(16)
        ))
        if request.targets.isEmpty {
            return AIProposal(summary: text.trimmingCharacters(in: .whitespacesAndNewlines), replacements: [], providerName: displayName)
        }
        return try AIProposalCodec.decode(text, providerName: displayName)
    }

    public func healthCheck() async throws -> String {
        try AIProviderHealthCheck.validated(
            try await run(prompt: AIProviderHealthCheck.prompt, workspaceKey: "Health-CodeBuddy")
        )
    }

    private func run(prompt: String, workspaceKey: String) async throws -> String {
        let directory = try ApplicationDirectories.supportDirectory()
            .appendingPathComponent("ProviderWorkspaces", isDirectory: true)
            .appendingPathComponent(workspaceKey, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = try await runner.run(
            executableURL: executableURL,
            arguments: Self.invocationArguments(for: profile),
            currentDirectoryURL: directory,
            input: Data(prompt.utf8)
        )
        guard output.exitCode == 0 else { throw ProcessRunnerError.nonZeroExit(output) }
        return try Self.resultText(in: output.standardOutput)
    }

    public static func invocationArguments(for profile: ProviderProfile) -> [String] {
        var arguments = [
            "-p", "--output-format", "json",
            "--disallowedTools", "Read,Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch"
        ]
        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: ["model": model]),
           let settings = String(data: data, encoding: .utf8) {
            arguments += ["--settings", settings]
        }
        return arguments
    }

    public static func resultText(in output: String) throws -> String {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse("CodeBuddy did not return a JSON object.")
        }
        if let result = object["result"] as? String { return result }
        if let structured = object["structured_output"],
           JSONSerialization.isValidJSONObject(structured),
           let encoded = try? JSONSerialization.data(withJSONObject: structured),
           let text = String(data: encoded, encoding: .utf8) {
            return text
        }
        throw AIProviderError.invalidResponse("CodeBuddy returned neither result nor structured_output.")
    }
}
