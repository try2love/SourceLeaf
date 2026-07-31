import Foundation

struct CodexAppServerTurnResult: Sendable, Equatable {
    var text: String
    var threadID: String

    init(text: String, threadID: String) {
        self.text = text
        self.threadID = threadID
    }
}

enum CodexAppServerError: Error, LocalizedError {
    case invalidMessage(String)
    case serverClosed(String)
    case serverError(String)
    case emptyResponse
    case busy

    var errorDescription: String? {
        switch self {
        case let .invalidMessage(message): "Codex app-server returned an invalid message: \(message)"
        case let .serverClosed(message): "Codex app-server stopped unexpectedly: \(message)"
        case let .serverError(message): "Codex app-server request failed: \(message)"
        case .emptyResponse: "Codex app-server returned an empty response."
        case .busy: "Codex app-server is already processing another turn."
        }
    }
}

enum CodexAppServerWire {
    static func initializeRequest(id: Int) -> [String: Any] {
        [
            "method": "initialize",
            "id": id,
            "params": [
                "clientInfo": [
                    "name": "sourceleaf",
                    "title": "SourceLeaf",
                    "version": "0.3.62"
                ]
            ]
        ]
    }

    static func threadStartRequest(
        id: Int,
        profile: ProviderProfile,
        cwd: URL
    ) -> [String: Any] {
        var params: [String: Any] = [
            "cwd": cwd.standardizedFileURL.path,
            "approvalPolicy": "never",
            "sandbox": "read-only",
            "ephemeral": true
        ]
        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty { params["model"] = model }
        return ["method": "thread/start", "id": id, "params": params]
    }

    static func threadResumeRequest(
        id: Int,
        threadID: String,
        profile: ProviderProfile,
        cwd: URL
    ) -> [String: Any] {
        var params: [String: Any] = [
            "threadId": threadID,
            "cwd": cwd.standardizedFileURL.path,
            "approvalPolicy": "never",
            "sandbox": "read-only",
            "excludeTurns": true
        ]
        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty { params["model"] = model }
        return ["method": "thread/resume", "id": id, "params": params]
    }

    static func turnStartRequest(
        id: Int,
        threadID: String,
        prompt: String,
        model: String,
        reasoningEffort: ModelReasoningEffort?
    ) -> [String: Any] {
        var params: [String: Any] = [
            "threadId": threadID,
            "input": [["type": "text", "text": prompt]]
        ]
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty { params["model"] = model }
        if let reasoningEffort { params["effort"] = reasoningEffort.rawValue }
        return ["method": "turn/start", "id": id, "params": params]
    }

    static func turnInterruptRequest(id: Int, threadID: String, turnID: String) -> [String: Any] {
        [
            "method": "turn/interrupt",
            "id": id,
            "params": ["threadId": threadID, "turnId": turnID]
        ]
    }

    static func threadID(from response: [String: Any]) -> String? {
        guard let result = response["result"] as? [String: Any],
              let thread = result["thread"] as? [String: Any] else { return nil }
        return thread["id"] as? String
    }

    static func turnID(from response: [String: Any]) -> String? {
        guard let result = response["result"] as? [String: Any],
              let turn = result["turn"] as? [String: Any] else { return nil }
        return turn["id"] as? String
    }

    static func providerEvent(
        from message: [String: Any],
        threadID: String,
        turnID: String?
    ) -> AIProviderEvent? {
        guard let method = message["method"] as? String,
              let params = message["params"] as? [String: Any],
              params["threadId"] as? String == threadID else { return nil }
        if let turnID, let messageTurnID = params["turnId"] as? String, messageTurnID != turnID {
            return nil
        }
        switch method {
        case "turn/started":
            return .working
        case "item/agentMessage/delta":
            guard let delta = params["delta"] as? String, !delta.isEmpty else { return nil }
            return .textDelta(delta)
        case "item/reasoning/summaryTextDelta", "item/reasoning/textDelta", "item/started":
            return .working
        default:
            return nil
        }
    }

    static func completedAgentText(
        from message: [String: Any],
        threadID: String,
        turnID: String?
    ) -> String? {
        guard message["method"] as? String == "item/completed",
              let params = message["params"] as? [String: Any],
              params["threadId"] as? String == threadID,
              let item = params["item"] as? [String: Any],
              item["type"] as? String == "agentMessage" else { return nil }
        if let turnID, params["turnId"] as? String != turnID { return nil }
        return item["text"] as? String
    }

    static func isTurnCompleted(
        _ message: [String: Any],
        threadID: String,
        turnID: String?
    ) -> Bool {
        guard message["method"] as? String == "turn/completed",
              let params = message["params"] as? [String: Any],
              params["threadId"] as? String == threadID,
              let turn = params["turn"] as? [String: Any] else { return false }
        guard let turnID else { return true }
        return turn["id"] as? String == turnID
    }

    static func turnError(
        from message: [String: Any],
        threadID: String,
        turnID: String?
    ) -> String? {
        guard let method = message["method"] as? String,
              let params = message["params"] as? [String: Any],
              params["threadId"] as? String == threadID else { return nil }
        if let turnID, let messageTurnID = params["turnId"] as? String, messageTurnID != turnID {
            return nil
        }
        if method == "error", params["willRetry"] as? Bool != true,
           let error = params["error"] as? [String: Any] {
            return error["message"] as? String
        }
        if method == "turn/completed", let turn = params["turn"] as? [String: Any],
           let error = turn["error"] as? [String: Any] {
            return error["message"] as? String
        }
        return nil
    }
}

actor CodexAppServerClient {
    private struct ThreadAttachment {
        var threadID: String
        var containsPriorTurns: Bool
    }

    static let shared = CodexAppServerClient()

    private var executableURL: URL?
    private var process: Process?
    private var inputHandle: FileHandle?
    private var lineMailbox: CodexAppServerLineMailbox?
    private var lineDecoder: CodexAppServerLineDecoder?
    private var stderrBuffer: CodexAppServerErrorBuffer?
    private var requestID = 0
    private var initialized = false
    private var attachedThreadIDs: Set<String> = []
    private var activeThreadID: String?
    private var activeTurnID: String?

    init() {}

    func runTurn(
        executableURL: URL,
        request: AIRequest,
        profile: ProviderProfile,
        onEvent: @escaping @Sendable (AIProviderEvent) -> Void
    ) async throws -> CodexAppServerTurnResult {
        guard activeThreadID == nil else { throw CodexAppServerError.busy }
        return try await withTaskCancellationHandler {
            try await performTurn(
                executableURL: executableURL,
                request: request,
                profile: profile,
                onEvent: onEvent
            )
        } onCancel: {
            Task { await self.interruptActiveTurn() }
        }
    }

    private func performTurn(
        executableURL: URL,
        request: AIRequest,
        profile: ProviderProfile,
        onEvent: @escaping @Sendable (AIProviderEvent) -> Void
    ) async throws -> CodexAppServerTurnResult {
        try Task.checkCancellation()
        try await ensureServer(executableURL: executableURL)
        let attachment = try await attachThread(
            existingThreadID: request.existingThreadID,
            profile: profile,
            cwd: request.projectRoot
        )
        let threadID = attachment.threadID
        activeThreadID = threadID
        onEvent(.sessionStarted)

        var promptRequest = request
        if attachment.containsPriorTurns {
            promptRequest.context.removeValue(forKey: "conversation-history")
        }
        let prompt = AIEditPromptBuilder.buildForCLI(promptRequest)
        let effort = profile.reasoningEffort ?? (request.targets.isEmpty ? .low : nil)
        let id = nextRequestID()
        try send(CodexAppServerWire.turnStartRequest(
            id: id,
            threadID: threadID,
            prompt: prompt,
            model: profile.model,
            reasoningEffort: effort
        ))

        var responseReceived = false
        var streamedText = ""
        var completedText: String?
        var responseStarted = false
        var finalError: String?

        defer {
            activeThreadID = nil
            activeTurnID = nil
        }

        while true {
            try Task.checkCancellation()
            let message = try await nextMessage()
            if Self.responseID(in: message) == id {
                try Self.throwIfErrorResponse(message)
                responseReceived = true
                activeTurnID = CodexAppServerWire.turnID(from: message)
                continue
            }
            if let event = CodexAppServerWire.providerEvent(
                from: message,
                threadID: threadID,
                turnID: activeTurnID
            ) {
                if case let .textDelta(delta) = event {
                    if !responseStarted {
                        responseStarted = true
                        onEvent(.responseStarted)
                    }
                    streamedText += delta
                }
                onEvent(event)
            }
            if let text = CodexAppServerWire.completedAgentText(
                from: message,
                threadID: threadID,
                turnID: activeTurnID
            ) {
                completedText = text
            }
            if let error = CodexAppServerWire.turnError(
                from: message,
                threadID: threadID,
                turnID: activeTurnID
            ) {
                finalError = error
            }
            if responseReceived,
               CodexAppServerWire.isTurnCompleted(message, threadID: threadID, turnID: activeTurnID) {
                if let finalError { throw CodexAppServerError.serverError(finalError) }
                let text = completedText ?? streamedText
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CodexAppServerError.emptyResponse
                }
                return CodexAppServerTurnResult(text: text, threadID: threadID)
            }
        }
    }

    private func attachThread(
        existingThreadID: String?,
        profile: ProviderProfile,
        cwd: URL
    ) async throws -> ThreadAttachment {
        if let existingThreadID, attachedThreadIDs.contains(existingThreadID) {
            return ThreadAttachment(threadID: existingThreadID, containsPriorTurns: true)
        }
        if let existingThreadID {
            let id = nextRequestID()
            do {
                let response = try await requestResponse(CodexAppServerWire.threadResumeRequest(
                    id: id,
                    threadID: existingThreadID,
                    profile: profile,
                    cwd: cwd
                ), id: id)
                guard let resumedID = CodexAppServerWire.threadID(from: response) else {
                    throw CodexAppServerError.invalidMessage("thread/resume omitted thread.id")
                }
                attachedThreadIDs.insert(resumedID)
                return ThreadAttachment(threadID: resumedID, containsPriorTurns: true)
            } catch let error as CodexAppServerError {
                if case .serverError = error {
                    attachedThreadIDs.remove(existingThreadID)
                } else {
                    throw error
                }
            }
        }

        let id = nextRequestID()
        let response = try await requestResponse(CodexAppServerWire.threadStartRequest(
            id: id,
            profile: profile,
            cwd: cwd
        ), id: id)
        guard let threadID = CodexAppServerWire.threadID(from: response) else {
            throw CodexAppServerError.invalidMessage("thread/start omitted thread.id")
        }
        attachedThreadIDs.insert(threadID)
        return ThreadAttachment(threadID: threadID, containsPriorTurns: false)
    }

    private func ensureServer(executableURL: URL) async throws {
        if let process, process.isRunning, initialized, self.executableURL == executableURL {
            return
        }
        stopServer()
        try startServer(executableURL: executableURL)
        let id = nextRequestID()
        _ = try await requestResponse(CodexAppServerWire.initializeRequest(id: id), id: id)
        initialized = true
    }

    private func startServer(executableURL: URL) throws {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let mailbox = CodexAppServerLineMailbox()
        let decoder = CodexAppServerLineDecoder(mailbox: mailbox)
        let errorBuffer = CodexAppServerErrorBuffer()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            decoder.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            errorBuffer.append(handle.availableData)
        }
        process.terminationHandler = { _ in decoder.finish() }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw CodexAppServerError.serverClosed(error.localizedDescription)
        }

        self.executableURL = executableURL
        self.process = process
        inputHandle = stdin.fileHandleForWriting
        lineMailbox = mailbox
        lineDecoder = decoder
        stderrBuffer = errorBuffer
        initialized = false
        attachedThreadIDs = []
    }

    private func stopServer() {
        if let process, process.isRunning { process.terminate() }
        inputHandle = nil
        lineMailbox = nil
        lineDecoder?.finish()
        lineDecoder = nil
        stderrBuffer = nil
        process = nil
        executableURL = nil
        initialized = false
        attachedThreadIDs = []
        activeThreadID = nil
        activeTurnID = nil
    }

    private func requestResponse(_ message: [String: Any], id: Int) async throws -> [String: Any] {
        try send(message)
        while true {
            let response = try await nextMessage()
            guard Self.responseID(in: response) == id else { continue }
            try Self.throwIfErrorResponse(response)
            return response
        }
    }

    private func interruptActiveTurn() {
        guard let threadID = activeThreadID, let turnID = activeTurnID else { return }
        let id = nextRequestID()
        try? send(CodexAppServerWire.turnInterruptRequest(id: id, threadID: threadID, turnID: turnID))
    }

    private func send(_ message: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(message) else {
            throw CodexAppServerError.invalidMessage("request was not valid JSON")
        }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        guard let inputHandle else { throw CodexAppServerError.serverClosed("stdin is unavailable") }
        do {
            try inputHandle.write(contentsOf: data)
        } catch {
            throw CodexAppServerError.serverClosed(error.localizedDescription)
        }
    }

    private func nextMessage() async throws -> [String: Any] {
        guard let lineMailbox else {
            throw CodexAppServerError.serverClosed(stderrBuffer?.text ?? "stdout is unavailable")
        }
        while let line = await lineMailbox.next() {
            guard let data = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            return message
        }
        throw CodexAppServerError.serverClosed(stderrBuffer?.text ?? "stdout closed")
    }

    private func nextRequestID() -> Int {
        requestID += 1
        return requestID
    }

    private static func responseID(in message: [String: Any]) -> Int? {
        if let id = message["id"] as? Int { return id }
        if let id = message["id"] as? NSNumber { return id.intValue }
        return nil
    }

    private static func throwIfErrorResponse(_ message: [String: Any]) throws {
        guard let error = message["error"] else { return }
        if let object = error as? [String: Any], let text = object["message"] as? String {
            throw CodexAppServerError.serverError(text)
        }
        throw CodexAppServerError.serverError(String(describing: error))
    }
}

private final class CodexAppServerLineDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var finished = false
    private let mailbox: CodexAppServerLineMailbox

    init(mailbox: CodexAppServerLineMailbox) {
        self.mailbox = mailbox
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        if data.isEmpty {
            finishLocked()
            return
        }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            if !line.isEmpty { mailbox.yield(String(decoding: line, as: UTF8.self)) }
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        finishLocked()
    }

    private func finishLocked() {
        guard !finished else { return }
        finished = true
        if !buffer.isEmpty { mailbox.yield(String(decoding: buffer, as: UTF8.self)) }
        buffer.removeAll(keepingCapacity: false)
        mailbox.finish()
    }
}

private final class CodexAppServerLineMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private var waiters: [CheckedContinuation<String?, Never>] = []
    private var finished = false

    func yield(_ line: String) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        if waiters.isEmpty {
            lines.append(line)
            lock.unlock()
            return
        }
        let waiter = waiters.removeFirst()
        lock.unlock()
        waiter.resume(returning: line)
    }

    func finish() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let pending = waiters
        waiters.removeAll(keepingCapacity: false)
        lock.unlock()
        for waiter in pending { waiter.resume(returning: nil) }
    }

    func next() async -> String? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if !lines.isEmpty {
                let line = lines.removeFirst()
                lock.unlock()
                continuation.resume(returning: line)
                return
            }
            if finished {
                lock.unlock()
                continuation.resume(returning: nil)
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }
}

private final class CodexAppServerErrorBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ additionalData: Data) {
        guard !additionalData.isEmpty else { return }
        lock.lock()
        data.append(additionalData)
        if data.count > 24_000 { data.removeFirst(data.count - 24_000) }
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
