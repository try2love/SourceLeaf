import Foundation

public enum BuildStatus: String, Sendable {
    case succeeded
    case failed
    case cancelled
}

public struct BuildResult: Sendable {
    public var status: BuildStatus
    public var command: [String]
    public var outputDirectory: URL
    public var pdfURL: URL?
    public var syncTeXURL: URL?
    public var log: String
    public var exitCode: Int32
    public var startedAt: Date
    public var finishedAt: Date

    public init(
        status: BuildStatus,
        command: [String],
        outputDirectory: URL,
        pdfURL: URL?,
        syncTeXURL: URL?,
        log: String,
        exitCode: Int32,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.status = status
        self.command = command
        self.outputDirectory = outputDirectory
        self.pdfURL = pdfURL
        self.syncTeXURL = syncTeXURL
        self.log = log
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public enum CompilerError: Error, LocalizedError {
    case rootDocumentMissing
    case engineUnavailable
    case invalidCustomCommand

    public var errorDescription: String? {
        switch self {
        case .rootDocumentMissing: "Choose a root LaTeX document before compiling."
        case .engineUnavailable: "No LaTeX engine is available. Install the managed engine or configure an external toolchain."
        case .invalidCustomCommand: "The custom build command is empty or invalid."
        }
    }
}

public actor CompilerService {
    private let runner: ProcessRunner
    private let fileManager: FileManager
    private var activeBuild: Task<BuildResult, Error>?

    public init(runner: ProcessRunner = ProcessRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func cancel() {
        activeBuild?.cancel()
        activeBuild = nil
    }

    public func build(
        projectRoot: URL,
        rootDocument: String,
        configuration: BuildConfiguration,
        managedTectonicURL: URL? = nil
    ) async throws -> BuildResult {
        activeBuild?.cancel()
        let task = Task {
            try await performBuild(
                projectRoot: projectRoot,
                rootDocument: rootDocument,
                configuration: configuration,
                managedTectonicURL: managedTectonicURL
            )
        }
        activeBuild = task
        defer { activeBuild = nil }
        return try await task.value
    }

    private func performBuild(
        projectRoot: URL,
        rootDocument: String,
        configuration: BuildConfiguration,
        managedTectonicURL: URL?
    ) async throws -> BuildResult {
        let rootURL = try SourceTargetService.validatedURL(relativePath: rootDocument, projectRoot: projectRoot)
        guard fileManager.fileExists(atPath: rootURL.path) else { throw CompilerError.rootDocumentMissing }

        let outputDirectory = try buildDirectory(for: projectRoot)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let invocation = try resolveInvocation(
            rootURL: rootURL,
            projectRoot: projectRoot,
            outputDirectory: outputDirectory,
            configuration: configuration,
            managedTectonicURL: managedTectonicURL
        )

        let startedAt = Date()
        let output = try await runner.run(
            executableURL: invocation.executable,
            arguments: invocation.arguments,
            currentDirectoryURL: projectRoot
        )
        let finishedAt = Date()
        let basename = rootURL.deletingPathExtension().lastPathComponent
        let pdfURL = outputDirectory.appendingPathComponent(basename).appendingPathExtension("pdf")
        let syncURL = outputDirectory.appendingPathComponent(basename).appendingPathExtension("synctex.gz")
        let succeeded = output.exitCode == 0 && fileManager.fileExists(atPath: pdfURL.path)
        let log = (["$ " + ([invocation.executable.path] + invocation.arguments).joined(separator: " "), output.standardOutput, output.standardError])
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return BuildResult(
            status: succeeded ? .succeeded : .failed,
            command: [invocation.executable.path] + invocation.arguments,
            outputDirectory: outputDirectory,
            pdfURL: succeeded ? pdfURL : nil,
            syncTeXURL: fileManager.fileExists(atPath: syncURL.path) ? syncURL : nil,
            log: log,
            exitCode: output.exitCode,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    private func resolveInvocation(
        rootURL: URL,
        projectRoot: URL,
        outputDirectory: URL,
        configuration: BuildConfiguration,
        managedTectonicURL: URL?
    ) throws -> (executable: URL, arguments: [String]) {
        let relativeRoot = rootURL.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
        let latexmk = ExecutableLocator.find("latexmk")
        let tectonic = managedTectonicURL.flatMap {
            FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil
        } ?? ExecutableLocator.find("tectonic")

        let engine: BuildEngine = {
            guard configuration.engine == .automatic else { return configuration.engine }
            return latexmk != nil ? .latexmkPDFLaTeX : .tectonic
        }()

        switch engine {
        case .automatic:
            throw CompilerError.engineUnavailable
        case .tectonic:
            guard let tectonic else { throw CompilerError.engineUnavailable }
            var arguments = ["--synctex", "--keep-logs", "--outdir", outputDirectory.path]
            if configuration.shellEscape { arguments.append("--untrusted") }
            arguments.append(relativeRoot)
            return (tectonic, arguments)
        case .latexmkPDFLaTeX, .latexmkXeLaTeX, .latexmkLuaLaTeX:
            guard let latexmk else { throw CompilerError.engineUnavailable }
            let mode: String = switch engine {
            case .latexmkXeLaTeX: "-xelatex"
            case .latexmkLuaLaTeX: "-lualatex"
            default: "-pdf"
            }
            var arguments = [mode, "-interaction=nonstopmode", "-synctex=1", "-outdir=" + outputDirectory.path]
            if configuration.shellEscape { arguments.append("-shell-escape") }
            arguments.append(relativeRoot)
            return (latexmk, arguments)
        case .custom:
            let command = configuration.customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { throw CompilerError.invalidCustomCommand }
            let expanded = command
                .replacingOccurrences(of: "{{root}}", with: shellQuoted(relativeRoot))
                .replacingOccurrences(of: "{{output}}", with: shellQuoted(outputDirectory.path))
            return (URL(fileURLWithPath: "/bin/zsh"), ["-lc", expanded])
        }
    }

    private func buildDirectory(for projectRoot: URL) throws -> URL {
        let cacheRoot = try ApplicationDirectories.cacheDirectory()
        let key = SourceTargetService.hash(projectRoot.standardizedFileURL.path)
        return cacheRoot.appendingPathComponent("Build", isDirectory: true).appendingPathComponent(String(key.prefix(16)), isDirectory: true)
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
