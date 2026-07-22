import Foundation
import Testing
@testable import SourceLeafCore

@Test func legacyBuildConfigurationDefaultsToTrialCompilation() throws {
    let legacy = """
    {
      "engine": "automatic",
      "customCommand": "",
      "autoBuild": true,
      "debounceSeconds": 1.5,
      "shellEscape": false
    }
    """
    let decoded = try JSONDecoder().decode(BuildConfiguration.self, from: Data(legacy.utf8))
    #expect(decoded.trialCompileBeforeAccept)
}

@Test func trialBuildUsesACopyAndLeavesOriginalSourceUntouched() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SourceLeafTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceURL = root.appendingPathComponent("main.tex")
    let original = "\\documentclass{article}\n\\begin{document}\nOriginal\n\\end{document}\n"
    let candidate = original.replacingOccurrences(of: "Original", with: "Candidate")
    try Data(original.utf8).write(to: sourceURL)

    let configuration = BuildConfiguration(
        engine: .custom,
        customCommand: "/usr/bin/touch {{output}}/main.pdf",
        autoBuild: false
    )
    let result = try await CompilerService().trialBuild(
        projectRoot: root,
        rootDocument: "main.tex",
        editedRelativePath: "main.tex",
        editedText: candidate,
        configuration: configuration
    )

    #expect(result.status == .succeeded)
    #expect(try String(contentsOf: sourceURL, encoding: .utf8) == original)
}

@Test func lastSuccessfulPDFCanBeRestoredWithoutRecompiling() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SourceLeafCachedPDFTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("\\documentclass{article}\n".utf8).write(to: root.appendingPathComponent("main.tex"))

    let compiler = CompilerService()
    let result = try await compiler.build(
        projectRoot: root,
        rootDocument: "main.tex",
        configuration: BuildConfiguration(
            engine: .custom,
            customCommand: "/usr/bin/touch {{output}}/main.pdf",
            autoBuild: false
        )
    )
    defer { try? FileManager.default.removeItem(at: result.outputDirectory) }

    let restored = try await CompilerService().cachedSuccessfulBuild(
        projectRoot: root,
        rootDocument: "main.tex"
    )
    #expect(restored?.status == .succeeded)
    #expect(restored?.reusedOutput == true)
    #expect(restored?.pdfURL == result.pdfURL)
}
