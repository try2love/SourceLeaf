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
    public var reusedOutput: Bool

    public init(
        status: BuildStatus,
        command: [String],
        outputDirectory: URL,
        pdfURL: URL?,
        syncTeXURL: URL?,
        log: String,
        exitCode: Int32,
        startedAt: Date,
        finishedAt: Date,
        reusedOutput: Bool = false
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
        self.reusedOutput = reusedOutput
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

public enum ManagedTectonicLocator {
    public static func resolve(
        bundleResourceURL: URL?,
        supportDirectory: URL?,
        architecture: String
    ) -> URL? {
        let bundleCandidate = bundleResourceURL?
            .appendingPathComponent("Engines", isDirectory: true)
            .appendingPathComponent(architecture, isDirectory: true)
            .appendingPathComponent("tectonic")
        if let bundleCandidate,
           FileManager.default.isExecutableFile(atPath: bundleCandidate.path) {
            return bundleCandidate
        }

        let supportCandidate = supportDirectory?
            .appendingPathComponent("Engines", isDirectory: true)
            .appendingPathComponent("tectonic")
        if let supportCandidate,
           FileManager.default.isExecutableFile(atPath: supportCandidate.path) {
            return supportCandidate
        }
        return nil
    }
}

public actor CompilerService {
    private struct BuildManifest: Codable {
        var fingerprint: String
        var command: [String]
    }

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

    /// Returns the last successful artifact for a project without compiling.
    /// The caller must present it as cached output because source files may
    /// have changed since the manifest was written.
    public func cachedSuccessfulBuild(
        projectRoot: URL,
        rootDocument: String
    ) throws -> BuildResult? {
        let rootURL = try SourceTargetService.validatedURL(relativePath: rootDocument, projectRoot: projectRoot)
        let outputDirectory = try buildDirectory(for: projectRoot)
        let manifestURL = outputDirectory.appendingPathComponent(".sourceleaf-build-manifest.json")
        let basename = rootURL.deletingPathExtension().lastPathComponent
        let pdfURL = outputDirectory.appendingPathComponent(basename).appendingPathExtension("pdf")
        guard fileManager.fileExists(atPath: pdfURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(BuildManifest.self, from: data) else { return nil }
        let syncURL = outputDirectory.appendingPathComponent(basename).appendingPathExtension("synctex.gz")
        let modified = (try? pdfURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return BuildResult(
            status: .succeeded,
            command: manifest.command,
            outputDirectory: outputDirectory,
            pdfURL: pdfURL,
            syncTeXURL: fileManager.fileExists(atPath: syncURL.path) ? syncURL : nil,
            log: "SourceLeaf: restored the last successful PDF from cache.",
            exitCode: 0,
            startedAt: modified,
            finishedAt: modified,
            reusedOutput: true
        )
    }

    public func build(
        projectRoot: URL,
        rootDocument: String,
        configuration: BuildConfiguration,
        managedTectonicURL: URL? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> BuildResult {
        activeBuild?.cancel()
        let task = Task {
            try await performBuild(
                projectRoot: projectRoot,
                rootDocument: rootDocument,
                configuration: configuration,
                managedTectonicURL: managedTectonicURL,
                onOutput: onOutput
            )
        }
        activeBuild = task
        defer { activeBuild = nil }
        return try await task.value
    }

    public func trialBuild(
        projectRoot: URL,
        rootDocument: String,
        editedRelativePath: String,
        editedText: String,
        configuration: BuildConfiguration,
        managedTectonicURL: URL? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> BuildResult {
        let cache = try ApplicationDirectories.cacheDirectory()
        let trialRoot = cache
            .appendingPathComponent("Trials", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        var generatedOutput: URL?
        defer {
            try? fileManager.removeItem(at: trialRoot)
            if let generatedOutput { try? fileManager.removeItem(at: generatedOutput) }
        }

        try copyProject(from: projectRoot, to: trialRoot)
        let candidateURL = try SourceTargetService.validatedURL(
            relativePath: editedRelativePath,
            projectRoot: trialRoot
        )
        try Data(editedText.utf8).write(to: candidateURL, options: [.atomic])
        let result = try await build(
            projectRoot: trialRoot,
            rootDocument: rootDocument,
            configuration: configuration,
            managedTectonicURL: managedTectonicURL,
            onOutput: onOutput
        )
        generatedOutput = result.outputDirectory
        return result
    }

    private func performBuild(
        projectRoot: URL,
        rootDocument: String,
        configuration: BuildConfiguration,
        managedTectonicURL: URL?,
        onOutput: (@Sendable (String) -> Void)?
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

        let command = [invocation.executable.path] + invocation.arguments
        let fingerprint = try buildFingerprint(
            projectRoot: projectRoot,
            rootDocument: rootDocument,
            configuration: configuration,
            command: command
        )
        let manifestURL = outputDirectory.appendingPathComponent(".sourceleaf-build-manifest.json")
        let basename = rootURL.deletingPathExtension().lastPathComponent
        let pdfURL = outputDirectory.appendingPathComponent(basename).appendingPathExtension("pdf")
        let syncURL = outputDirectory.appendingPathComponent(basename).appendingPathExtension("synctex.gz")
        if let data = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONDecoder().decode(BuildManifest.self, from: data),
           manifest.fingerprint == fingerprint,
           manifest.command == command,
           fileManager.fileExists(atPath: pdfURL.path) {
            let now = Date()
            onOutput?("SourceLeaf: project unchanged; reusing the last successful PDF.\n")
            return BuildResult(
                status: .succeeded,
                command: command,
                outputDirectory: outputDirectory,
                pdfURL: pdfURL,
                syncTeXURL: fileManager.fileExists(atPath: syncURL.path) ? syncURL : nil,
                log: "$ " + command.joined(separator: " ") + "\nSourceLeaf: project unchanged; reused the last successful PDF.",
                exitCode: 0,
                startedAt: now,
                finishedAt: now,
                reusedOutput: true
            )
        }

        let startedAt = Date()
        var actualArguments = invocation.arguments
        var attemptLogs: [String] = []
        if let cachedArguments = Self.cachedTectonicArguments(
            executableURL: invocation.executable,
            arguments: invocation.arguments
        ) {
            actualArguments = cachedArguments
        }
        var output = try await runner.run(
            executableURL: invocation.executable,
            arguments: actualArguments,
            currentDirectoryURL: projectRoot,
            onOutput: onOutput
        )
        attemptLogs.append(
            Self.log(executableURL: invocation.executable, arguments: actualArguments, output: output)
        )
        if actualArguments != invocation.arguments, Self.requiresNetworkRetry(output) {
            let fallback = "SourceLeaf: a required TeX resource is not cached; retrying with network access.\n"
            onOutput?(fallback)
            output = try await runner.run(
                executableURL: invocation.executable,
                arguments: invocation.arguments,
                currentDirectoryURL: projectRoot,
                onOutput: onOutput
            )
            actualArguments = invocation.arguments
            attemptLogs.append(fallback.trimmingCharacters(in: .whitespacesAndNewlines))
            attemptLogs.append(
                Self.log(executableURL: invocation.executable, arguments: actualArguments, output: output)
            )
        }
        let finishedAt = Date()
        let succeeded = output.exitCode == 0 && fileManager.fileExists(atPath: pdfURL.path)
        let log = attemptLogs.joined(separator: "\n")

        let result = BuildResult(
            status: succeeded ? .succeeded : .failed,
            command: command,
            outputDirectory: outputDirectory,
            pdfURL: succeeded ? pdfURL : nil,
            syncTeXURL: fileManager.fileExists(atPath: syncURL.path) ? syncURL : nil,
            log: log,
            exitCode: output.exitCode,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
        if succeeded {
            let manifest = BuildManifest(fingerprint: fingerprint, command: command)
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
        }
        return result
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
            if configuration.shellEscape {
                arguments += ["-Z", "shell-escape", "-Z", "shell-escape-cwd=\(projectRoot.path)"]
            } else {
                arguments.append("--untrusted")
            }
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

    static func cachedTectonicArguments(executableURL: URL, arguments: [String]) -> [String]? {
        guard executableURL.lastPathComponent == "tectonic",
              !arguments.contains("--only-cached"),
              !arguments.contains("-C") else { return nil }
        return ["--only-cached"] + arguments
    }

    static func requiresNetworkRetry(_ output: ProcessOutput) -> Bool {
        guard output.exitCode != 0 else { return false }
        let message = (output.standardOutput + "\n" + output.standardError).lowercased()
        return message.contains("not found")
            || message.contains("not available in the cache")
            || message.contains("cache miss")
            || message.contains("no such file")
            || message.contains("failed to retrieve")
    }

    private static func log(executableURL: URL, arguments: [String], output: ProcessOutput) -> String {
        (["$ " + ([executableURL.path] + arguments).joined(separator: " "), output.standardOutput, output.standardError])
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func buildFingerprint(
        projectRoot: URL,
        rootDocument: String,
        configuration: BuildConfiguration,
        command: [String]
    ) throws -> String {
        let supportedExtensions: Set<String> = [
            "tex", "bib", "sty", "cls", "bst", "bbx", "cbx", "def", "cfg", "clo",
            "png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp", "svg", "eps", "pdf"
        ]
        let excludedDirectories: Set<String> = [".git", ".build", "build", "DerivedData", "临时文件"]
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return SourceTargetService.hash(rootDocument) }
        let prefix = projectRoot.path.hasSuffix("/") ? projectRoot.path : projectRoot.path + "/"
        var records: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isDirectory == true, excludedDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true,
                  supportedExtensions.contains(url.pathExtension.lowercased()),
                  url.path.hasPrefix(prefix) else { continue }
            let relativePath = String(url.path.dropFirst(prefix.count))
            let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            records.append("\(relativePath)|\(values.fileSize ?? 0)|\(modified)")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let configurationData = try encoder.encode(configuration)
        let configurationText = String(decoding: configurationData, as: UTF8.self)
        return SourceTargetService.hash(
            ([rootDocument, configurationText, command.joined(separator: "\u{1f}")] + records.sorted())
                .joined(separator: "\n")
        )
    }

    private func copyProject(from sourceRoot: URL, to destinationRoot: URL) throws {
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else { return }
        let excludedDirectories: Set<String> = [".git", ".build", "build", "DerivedData", "临时文件"]
        let sourcePrefix = sourceRoot.path.hasSuffix("/") ? sourceRoot.path : sourceRoot.path + "/"

        for case let sourceURL as URL in enumerator {
            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values.isDirectory == true, excludedDirectories.contains(sourceURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard sourceURL.path.hasPrefix(sourcePrefix) else { continue }
            let relativePath = String(sourceURL.path.dropFirst(sourcePrefix.count))
            let destinationURL = destinationRoot.appendingPathComponent(relativePath)
            if values.isDirectory == true {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            } else if values.isRegularFile == true || values.isSymbolicLink == true {
                try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
