import Foundation
import Testing
@testable import SourceLeafCore

@Test func decodesProposalFromMarkdownWrappedJSON() throws {
    let targetID = UUID()
    let response = """
    ```json
    {"summary":"Polished","replacements":[{"target_id":"\(targetID.uuidString)","replacement":"New text","explanation":"Clearer"}]}
    ```
    """
    let proposal = try AIProposalCodec.decode(response, providerName: "Test")
    #expect(proposal.summary == "Polished")
    #expect(proposal.replacements.first?.targetID == targetID)
}

@Test func extractsLastCodexAgentMessage() {
    let lines = """
    {"type":"thread.started","thread_id":"abc"}
    {"type":"item.completed","item":{"type":"agent_message","text":"first"}}
    {"type":"item.completed","item":{"type":"agent_message","text":"last"}}
    """
    #expect(CodexCLIProvider.lastAgentMessage(in: lines) == "last")
}

@Test func localCodexInvocationUsesTheSelectedModelAndReasoningEffort() {
    let profile = ProviderProfile(
        name: "Local Codex",
        kind: .localCodex,
        model: "gpt-5.6-terra",
        reasoningEffort: .high
    )
    let arguments = CodexCLIProvider.invocationArguments(for: profile)

    let modelIndex = arguments.firstIndex(of: "--model")
    let configIndex = arguments.firstIndex(of: "--config")
    let sandboxIndex = arguments.firstIndex(of: "--sandbox")
    #expect(modelIndex.map { arguments[$0 + 1] } == "gpt-5.6-terra")
    #expect(configIndex.map { arguments[$0 + 1] } == "model_reasoning_effort=\"high\"")
    #expect(sandboxIndex.map { arguments[$0 + 1] } == "read-only")
    #expect(arguments.contains("--ephemeral"))
}

@Test func codeBuddyInvocationIsHeadlessModelAwareAndToolRestricted() throws {
    let profile = ProviderProfile(name: "CodeBuddy", kind: .codeBuddy, model: "claude-test")
    let arguments = CodeBuddyCLIProvider.invocationArguments(for: profile)
    #expect(arguments.contains("-p"))
    #expect(arguments.contains("json"))
    #expect(arguments.contains("--disallowedTools"))
    #expect(arguments.contains("--settings"))
    #expect(!arguments.contains("--dangerously-skip-permissions"))
    #expect(try CodeBuddyCLIProvider.resultText(in: #"{"result":"hello"}"#) == "hello")
}

@Test func providerHealthRequiresAnExactHelloResponse() throws {
    #expect(try AIProviderHealthCheck.validated("  hello\n") == "hello")
    #expect(throws: AIProviderError.self) {
        try AIProviderHealthCheck.validated("hello there")
    }
}

@Test func legacyProviderProfileDefaultsToCodexManagedReasoning() throws {
    let id = UUID()
    let data = Data("""
    {"id":"\(id.uuidString)","name":"Local Codex","kind":"localCodex","model":"","baseURL":null,"headers":{},"command":null,"enabled":true}
    """.utf8)
    let profile = try JSONDecoder().decode(ProviderProfile.self, from: data)
    #expect(profile.reasoningEffort == nil)
}

@Test func reasoningEffortMapsToOpenAIAndCompatibleRequestBodies() throws {
    let openAI = HTTPAIProvider(
        profile: ProviderProfile(name: "OpenAI", kind: .openAI, model: "gpt-test", reasoningEffort: .high),
        apiKey: "test-key"
    )
    let openAIRequest = try openAI.makeRequest(prompt: "Review")
    let openAIData = try #require(openAIRequest.httpBody)
    let openAIBody = try #require(
        JSONSerialization.jsonObject(with: openAIData) as? [String: Any]
    )
    let reasoning = try #require(openAIBody["reasoning"] as? [String: String])
    #expect(reasoning["effort"] == "high")

    let compatible = HTTPAIProvider(
        profile: ProviderProfile(
            name: "Compatible",
            kind: .openAICompatible,
            model: "model-test",
            baseURL: "http://127.0.0.1:1234/v1/chat/completions",
            reasoningEffort: .xhigh
        ),
        apiKey: nil
    )
    let compatibleRequest = try compatible.makeRequest(prompt: "Review")
    let compatibleData = try #require(compatibleRequest.httpBody)
    let compatibleBody = try #require(
        JSONSerialization.jsonObject(with: compatibleData) as? [String: Any]
    )
    #expect(compatibleBody["reasoning_effort"] as? String == "xhigh")
}

@Test func builtInPromptsContainTheTemperedAcademicReviewer() throws {
    let prompt = try #require(BuiltInPrompts.all.first { $0.id == "reviewer-tempered.v1" })
    #expect(prompt.nameZH == "略微缓和的审稿人")
    #expect(prompt.bodyZH.contains("严苛、精准且富有洞察"))
    #expect(prompt.bodyZH.contains("必须解决的核心问题"))
    #expect(prompt.body.contains("Critical Issues Requiring Mandatory Revision"))
    #expect(!prompt.body.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) })
}

@Test func promptClearlySeparatesTargetsFromContext() throws {
    let target = try SourceTargetService.target(
        in: "Selected text",
        relativePath: "main.tex",
        utf16Range: NSRange(location: 0, length: 13)
    )
    let request = AIRequest(
        instruction: "Polish",
        targets: [target],
        context: ["section": "Read only"],
        projectRoot: URL(fileURLWithPath: "/tmp")
    )
    let prompt = AIEditPromptBuilder.build(request)
    #expect(prompt.contains("Writable targets"))
    #expect(prompt.contains("Read-only context"))
    #expect(prompt.contains(target.id.uuidString))
}

@Test func localCodexProviderSmokeWhenExplicitlyEnabled() async throws {
    guard ProcessInfo.processInfo.environment["SOURCELEAF_RUN_CODEX_TEST"] == "1" else { return }
    let provider = try CodexCLIProvider()
    let request = AIRequest(
        instruction: "Return an empty replacements array and a short summary confirming the SourceLeaf protocol.",
        targets: [],
        context: [:],
        projectRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    )
    let proposal = try await provider.generateProposal(for: request)
    #expect(proposal.replacements.isEmpty)
    #expect(!proposal.summary.isEmpty)
}
