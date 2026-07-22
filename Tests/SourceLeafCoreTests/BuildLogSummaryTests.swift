import Foundation
import Testing
@testable import SourceLeafCore

@Test func buildLogSummaryExplainsAComplexTectonicRun() {
    let log = """
    note: downloading acmart.cls
    note: Running TeX ...
    warning: main.tex:42: Overfull \\hbox
    note: Running BibTeX ...
    error: failed to open an optional resource
    note: Running xdvipdfmx ...
    """

    let summary = BuildLogSummary(log: log)

    #expect(summary.downloadCount == 1)
    #expect(summary.warningCount == 1)
    #expect(summary.errorCount == 1)
    #expect(summary.phase == .renderingPDF)
}

@Test func processRunnerStreamsOutputWhileKeepingTheFinalResult() async throws {
    let received = ThreadSafeText()
    let result = try await ProcessRunner().run(
        executableURL: URL(fileURLWithPath: "/bin/zsh"),
        arguments: ["-c", "print -n 'first'; sleep 0.1; print -u2 -n 'second'"],
        onOutput: { received.append($0) }
    )

    #expect(received.value.contains("first"))
    #expect(received.value.contains("second"))
    #expect(result.standardOutput == "first")
    #expect(result.standardError == "second")
}

@Test func compilerServiceForwardsLiveBuildProgress() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SourceLeaf-build-progress-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("\\documentclass{article}\n".utf8).write(to: root.appendingPathComponent("main.tex"))

    let received = ThreadSafeText()
    let configuration = BuildConfiguration(
        engine: .custom,
        customCommand: "print -n 'note: Running TeX ...'; /usr/bin/touch {{output}}/main.pdf",
        autoBuild: false
    )
    let result = try await CompilerService().build(
        projectRoot: root,
        rootDocument: "main.tex",
        configuration: configuration,
        onOutput: { received.append($0) }
    )

    #expect(result.status == .succeeded)
    #expect(received.value.contains("Running TeX"))
}

@Test func tectonicPrefersCachedResourcesAndRetriesOnlyForMissingFiles() {
    let arguments = ["--synctex", "--outdir", "/tmp/output", "main.tex"]
    #expect(CompilerService.cachedTectonicArguments(
        executableURL: URL(fileURLWithPath: "/tmp/tectonic"),
        arguments: arguments
    ) == ["--only-cached"] + arguments)
    #expect(CompilerService.cachedTectonicArguments(
        executableURL: URL(fileURLWithPath: "/tmp/latexmk"),
        arguments: arguments
    ) == nil)
    #expect(CompilerService.requiresNetworkRetry(ProcessOutput(
        exitCode: 1,
        standardOutput: "note: using only cached resource files",
        standardError: "LaTeX Error: File `article.cls' not found."
    )))
    #expect(!CompilerService.requiresNetworkRetry(ProcessOutput(
        exitCode: 1,
        standardOutput: "",
        standardError: "Undefined control sequence."
    )))
}

@Test func unchangedProjectReusesTheSuccessfulBuildWithoutLaunchingTheToolAgain() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SourceLeaf-build-cache-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("\\documentclass{article}\n".utf8).write(to: root.appendingPathComponent("main.tex"))
    let counter = root.appendingPathComponent("invocations.txt")
    let escapedCounter = counter.path.replacingOccurrences(of: "'", with: "'\\''")
    let configuration = BuildConfiguration(
        engine: .custom,
        customCommand: "print x >> '\(escapedCounter)'; /usr/bin/touch {{output}}/main.pdf",
        autoBuild: false
    )
    let compiler = CompilerService()

    let first = try await compiler.build(
        projectRoot: root,
        rootDocument: "main.tex",
        configuration: configuration
    )
    let second = try await compiler.build(
        projectRoot: root,
        rootDocument: "main.tex",
        configuration: configuration
    )

    #expect(first.status == .succeeded)
    #expect(second.status == .succeeded)
    let invocations = try String(contentsOf: counter, encoding: .utf8)
        .split(whereSeparator: \.isNewline)
    #expect(invocations.count == 1)
}

@Test func realProjectSecondBuildUsesTheFastPathWhenExplicitlyEnabled() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["SOURCELEAF_RUN_REAL_BUILD"] == "1",
          let projectPath = environment["SOURCELEAF_REAL_PROJECT"],
          let enginePath = environment["SOURCELEAF_MANAGED_TECTONIC"] else { return }
    let root = URL(fileURLWithPath: projectPath, isDirectory: true)
    let engine = URL(fileURLWithPath: enginePath)
    let compiler = CompilerService()
    let configuration = BuildConfiguration(engine: .tectonic, autoBuild: false)

    let coldStart = Date()
    let first = try await compiler.build(
        projectRoot: root,
        rootDocument: "MutedRAG.tex",
        configuration: configuration,
        managedTectonicURL: engine
    )
    let coldDuration = Date().timeIntervalSince(coldStart)
    let warmStart = Date()
    let second = try await compiler.build(
        projectRoot: root,
        rootDocument: "MutedRAG.tex",
        configuration: configuration,
        managedTectonicURL: engine
    )
    let warmDuration = Date().timeIntervalSince(warmStart)

    #expect(first.status == .succeeded)
    #expect(second.status == .succeeded)
    #expect(second.reusedOutput)
    #expect(warmDuration < 1)
    print("SOURCELEAF_REAL_BUILD cold=\(coldDuration) warm=\(warmDuration)")
}

private final class ThreadSafeText: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    func append(_ text: String) {
        lock.lock()
        storage += text
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
