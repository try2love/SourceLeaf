import Foundation

public struct ProcessOutput: Sendable, Equatable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public enum ProcessRunnerError: Error, LocalizedError {
    case launchFailed(String)
    case nonZeroExit(ProcessOutput)

    public var errorDescription: String? {
        switch self {
        case let .launchFailed(message): message
        case let .nonZeroExit(output):
            output.standardError.isEmpty
                ? "The command exited with status \(output.exitCode)."
                : output.standardError
        }
    }
}

public final class ProcessRunner: @unchecked Sendable {
    public init() {}

    public func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil,
        input: Data? = nil
    ) async throws -> ProcessOutput {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        let stdoutBuffer = LockedDataBuffer()
        let stderrBuffer = LockedDataBuffer()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = stdout
        process.standardError = stderr
        if input != nil { process.standardInput = stdin }
        if let environment { process.environment = environment }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutBuffer.append(data)
                onOutput?(String(decoding: data, as: UTF8.self))
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrBuffer.append(data)
                onOutput?(String(decoding: data, as: UTF8.self))
            }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { completed in
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    let stdoutTail = stdout.fileHandleForReading.readDataToEndOfFile()
                    let stderrTail = stderr.fileHandleForReading.readDataToEndOfFile()
                    stdoutBuffer.append(stdoutTail)
                    stderrBuffer.append(stderrTail)
                    if !stdoutTail.isEmpty { onOutput?(String(decoding: stdoutTail, as: UTF8.self)) }
                    if !stderrTail.isEmpty { onOutput?(String(decoding: stderrTail, as: UTF8.self)) }
                    continuation.resume(returning: ProcessOutput(
                        exitCode: completed.terminationStatus,
                        standardOutput: String(decoding: stdoutBuffer.value, as: UTF8.self),
                        standardError: String(decoding: stderrBuffer.value, as: UTF8.self)
                    ))
                }

                do {
                    try process.run()
                    if let input {
                        DispatchQueue.global(qos: .userInitiated).async {
                            stdin.fileHandleForWriting.write(input)
                            try? stdin.fileHandleForWriting.close()
                        }
                    }
                } catch {
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ additionalData: Data) {
        guard !additionalData.isEmpty else { return }
        lock.lock()
        data.append(additionalData)
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

public enum ExecutableLocator {
    public static func find(_ name: String, extraPaths: [String] = []) -> URL? {
        let environmentPaths = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let commonPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/Library/TeX/texbin",
            NSHomeDirectory() + "/.local/bin",
            NSHomeDirectory() + "/bin",
            "/Applications/Codex.app/Contents/Resources"
        ]

        for directory in extraPaths + environmentPaths + commonPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
