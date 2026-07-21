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
