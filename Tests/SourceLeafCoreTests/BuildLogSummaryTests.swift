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
