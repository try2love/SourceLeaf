import Foundation

public enum DockZone: String, Codable, CaseIterable, Hashable, Sendable {
    case leading
    case center
    case trailing
    case bottom
}

public enum WorkspacePanel: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case project
    case source
    case image
    case pdf
    case codex
    case buildLog
    case history

    public var id: String { rawValue }
}

public struct DockLayout: Codable, Equatable, Sendable {
    public var zones: [DockZone: [WorkspacePanel]]
    public var selected: [DockZone: WorkspacePanel]

    public init(
        zones: [DockZone: [WorkspacePanel]] = [
            .leading: [.project],
            .center: [.source],
            .trailing: [.pdf, .codex],
            .bottom: [.buildLog]
        ],
        selected: [DockZone: WorkspacePanel] = [
            .leading: .project,
            .center: .source,
            .trailing: .pdf,
            .bottom: .buildLog
        ]
    ) {
        self.zones = zones
        self.selected = selected
    }

    public mutating func show(_ panel: WorkspacePanel, in zone: DockZone? = nil) {
        if contains(panel) { return }
        let target = zone ?? Self.defaultZone(for: panel)
        zones[target, default: []].append(panel)
        selected[target] = panel
    }

    public mutating func close(_ panel: WorkspacePanel) {
        for zone in DockZone.allCases {
            zones[zone]?.removeAll { $0 == panel }
            if selected[zone] == panel {
                selected[zone] = zones[zone]?.first
            }
        }
    }

    public mutating func move(_ panel: WorkspacePanel, to zone: DockZone) {
        close(panel)
        zones[zone, default: []].append(panel)
        selected[zone] = panel
    }

    public func contains(_ panel: WorkspacePanel) -> Bool {
        zones.values.contains { $0.contains(panel) }
    }

    public static func defaultZone(for panel: WorkspacePanel) -> DockZone {
        switch panel {
        case .project: .leading
        case .source, .image: .center
        case .pdf, .codex, .history: .trailing
        case .buildLog: .bottom
        }
    }

    public func zone(containing panel: WorkspacePanel) -> DockZone? {
        DockZone.allCases.first { zones[$0]?.contains(panel) == true }
    }

    public mutating func restore(_ panel: WorkspacePanel, to zone: DockZone?) {
        let target = zone ?? Self.defaultZone(for: panel)
        if contains(panel) { move(panel, to: target) }
        else {
            zones[target, default: []].append(panel)
            selected[target] = panel
        }
    }
}

public enum ContextScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case selection
    case nearby
    case section
    case document
    case project
    case custom

    public var id: String { rawValue }
}

public enum ChatSendBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case enter
    case shiftEnter

    public var id: String { rawValue }
}

public enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case localCodex
    case codeBuddy
    case openAI
    case openAICompatible
    case anthropic
    case gemini
    case ollama
    case lmStudio
    case customCLI

    public var id: String { rawValue }
}

public enum ModelReasoningEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max
    case ultra

    public var id: String { rawValue }
}

public struct ProviderProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ProviderKind
    public var model: String
    public var baseURL: String?
    public var headers: [String: String]
    public var command: String?
    public var enabled: Bool
    public var reasoningEffort: ModelReasoningEffort?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ProviderKind,
        model: String = "",
        baseURL: String? = nil,
        headers: [String: String] = [:],
        command: String? = nil,
        enabled: Bool = true,
        reasoningEffort: ModelReasoningEffort? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.model = model
        self.baseURL = baseURL
        self.headers = headers
        self.command = command
        self.enabled = enabled
        self.reasoningEffort = reasoningEffort
    }

    public static let localCodex = ProviderProfile(
        name: "Local Codex",
        kind: .localCodex
    )

    public static let localCodeBuddy = ProviderProfile(
        name: "Local CodeBuddy",
        kind: .codeBuddy
    )
}

public enum BuildEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case tectonic
    case latexmkPDFLaTeX
    case latexmkXeLaTeX
    case latexmkLuaLaTeX
    case custom

    public var id: String { rawValue }
}

public struct BuildConfiguration: Codable, Equatable, Sendable {
    public var engine: BuildEngine
    public var customCommand: String
    public var autoBuild: Bool
    public var debounceSeconds: Double
    public var shellEscape: Bool
    public var trialCompileBeforeAccept: Bool

    public init(
        engine: BuildEngine = .automatic,
        customCommand: String = "",
        autoBuild: Bool = true,
        debounceSeconds: Double = 1.5,
        shellEscape: Bool = false,
        trialCompileBeforeAccept: Bool = true
    ) {
        self.engine = engine
        self.customCommand = customCommand
        self.autoBuild = autoBuild
        self.debounceSeconds = min(5, max(0.5, debounceSeconds))
        self.shellEscape = shellEscape
        self.trialCompileBeforeAccept = trialCompileBeforeAccept
    }

    private enum CodingKeys: String, CodingKey {
        case engine, customCommand, autoBuild, debounceSeconds, shellEscape, trialCompileBeforeAccept
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            engine: try container.decodeIfPresent(BuildEngine.self, forKey: .engine) ?? .automatic,
            customCommand: try container.decodeIfPresent(String.self, forKey: .customCommand) ?? "",
            autoBuild: try container.decodeIfPresent(Bool.self, forKey: .autoBuild) ?? true,
            debounceSeconds: try container.decodeIfPresent(Double.self, forKey: .debounceSeconds) ?? 1.5,
            shellEscape: try container.decodeIfPresent(Bool.self, forKey: .shellEscape) ?? false,
            trialCompileBeforeAccept: try container.decodeIfPresent(Bool.self, forKey: .trialCompileBeforeAccept) ?? true
        )
    }
}

public struct ProjectConfiguration: Codable, Equatable, Sendable {
    public var rootDocument: String?
    public var build: BuildConfiguration
    public var defaultContextScope: ContextScope
    public var autoSave: Bool
    public var autoSaveDelaySeconds: Double
    public var showSelectionButton: Bool
    public var privateChatMode: Bool
    public var systemPrompt: String
    public var chatSendBehavior: ChatSendBehavior
    public var layout: DockLayout

    public init(
        rootDocument: String? = nil,
        build: BuildConfiguration = BuildConfiguration(),
        defaultContextScope: ContextScope = .section,
        autoSave: Bool = true,
        autoSaveDelaySeconds: Double = 1,
        showSelectionButton: Bool = true,
        privateChatMode: Bool = false,
        systemPrompt: String = "You are a helpful research and LaTeX assistant.",
        chatSendBehavior: ChatSendBehavior = .enter,
        layout: DockLayout = DockLayout()
    ) {
        self.rootDocument = rootDocument
        self.build = build
        self.defaultContextScope = defaultContextScope
        self.autoSave = autoSave
        self.autoSaveDelaySeconds = min(5, max(0.2, autoSaveDelaySeconds))
        self.showSelectionButton = showSelectionButton
        self.privateChatMode = privateChatMode
        self.systemPrompt = systemPrompt
        self.chatSendBehavior = chatSendBehavior
        self.layout = layout
    }

    private enum CodingKeys: String, CodingKey {
        case rootDocument, build, defaultContextScope, autoSave, autoSaveDelaySeconds
        case showSelectionButton, privateChatMode, systemPrompt, chatSendBehavior, layout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rootDocument: try container.decodeIfPresent(String.self, forKey: .rootDocument),
            build: try container.decodeIfPresent(BuildConfiguration.self, forKey: .build) ?? BuildConfiguration(),
            defaultContextScope: try container.decodeIfPresent(ContextScope.self, forKey: .defaultContextScope) ?? .section,
            autoSave: try container.decodeIfPresent(Bool.self, forKey: .autoSave) ?? true,
            autoSaveDelaySeconds: try container.decodeIfPresent(Double.self, forKey: .autoSaveDelaySeconds) ?? 1,
            showSelectionButton: try container.decodeIfPresent(Bool.self, forKey: .showSelectionButton) ?? true,
            privateChatMode: try container.decodeIfPresent(Bool.self, forKey: .privateChatMode) ?? false,
            systemPrompt: try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? "You are a helpful research and LaTeX assistant.",
            chatSendBehavior: try container.decodeIfPresent(ChatSendBehavior.self, forKey: .chatSendBehavior) ?? .enter,
            layout: try container.decodeIfPresent(DockLayout.self, forKey: .layout) ?? DockLayout()
        )
    }
}

public struct ProjectFile: Identifiable, Hashable, Sendable {
    public var relativePath: String
    public var url: URL
    public var kind: Kind

    public var id: String { relativePath }

    public enum Kind: String, Sendable {
        case tex
        case bibliography
        case style
        case image
        case pdf
        case other
    }

    public init(relativePath: String, url: URL, kind: Kind) {
        self.relativePath = relativePath
        self.url = url
        self.kind = kind
    }
}

public struct ProjectTreeNode: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var relativePath: String
    public var file: ProjectFile?
    public var children: [ProjectTreeNode]?

    public var isDirectory: Bool { file == nil }

    public init(
        id: String,
        name: String,
        relativePath: String,
        file: ProjectFile? = nil,
        children: [ProjectTreeNode]? = nil
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.file = file
        self.children = children
    }
}

public struct SourceLineLocation: Equatable, Sendable {
    public var line: Int
    public var utf16Location: Int

    public init(line: Int, utf16Location: Int) {
        self.line = line
        self.utf16Location = utf16Location
    }
}

public enum SourceLineMap {
    public static func lineNumber(in source: String, utf16Location requestedLocation: Int) -> Int {
        let text = source as NSString
        let location = min(max(0, requestedLocation), text.length)
        guard location > 0 else { return 1 }
        return 1 + text.substring(to: location).reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
    }

    public static func utf16Location(in source: String, line requestedLine: Int) -> Int {
        guard requestedLine > 1 else { return 0 }
        let text = source as NSString
        var location = 0
        var line = 1
        while location < text.length, line < requestedLine {
            var end = 0
            text.getLineStart(nil, end: &end, contentsEnd: nil, for: NSRange(location: location, length: 0))
            guard end > location else { break }
            location = end
            line += 1
        }
        return min(location, text.length)
    }

    public static func utf16Range(of selectedText: String, in source: String, line requestedLine: Int) -> NSRange? {
        let needle = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        let text = source as NSString
        let lineStart = utf16Location(in: source, line: requestedLine)
        guard lineStart < text.length else { return nil }
        var start = 0
        var end = 0
        var contentsEnd = 0
        text.getLineStart(
            &start,
            end: &end,
            contentsEnd: &contentsEnd,
            for: NSRange(location: lineStart, length: 0)
        )
        let lineRange = NSRange(location: start, length: max(0, contentsEnd - start))
        let match = text.range(of: needle, options: [.caseInsensitive], range: lineRange)
        return match.location == NSNotFound ? nil : match
    }

    public static func visibleLineStarts(in source: String, utf16Range: NSRange) -> [SourceLineLocation] {
        let text = source as NSString
        guard text.length > 0 else { return [SourceLineLocation(line: 1, utf16Location: 0)] }
        let safeLocation = min(max(0, utf16Range.location), text.length - 1)
        let safeEnd = min(text.length, max(safeLocation, NSMaxRange(utf16Range)))
        var lineStart = 0
        var lineEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: nil, for: NSRange(location: safeLocation, length: 0))
        let prefix = text.substring(to: lineStart)
        var lineNumber = 1 + prefix.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
        var result: [SourceLineLocation] = []
        while lineStart <= safeEnd, lineStart < text.length {
            result.append(SourceLineLocation(line: lineNumber, utf16Location: lineStart))
            var nextEnd = 0
            text.getLineStart(nil, end: &nextEnd, contentsEnd: nil, for: NSRange(location: lineStart, length: 0))
            guard nextEnd > lineStart else { break }
            lineStart = nextEnd
            lineNumber += 1
        }
        return result
    }
}

public struct SourceTarget: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var relativePath: String
    public var utf16Location: Int
    public var utf16Length: Int
    public var startLine: Int
    public var endLine: Int
    public var originalText: String
    public var contentHash: String

    public init(
        id: UUID = UUID(),
        relativePath: String,
        utf16Location: Int,
        utf16Length: Int,
        startLine: Int,
        endLine: Int,
        originalText: String,
        contentHash: String
    ) {
        self.id = id
        self.relativePath = relativePath
        self.utf16Location = utf16Location
        self.utf16Length = utf16Length
        self.startLine = startLine
        self.endLine = endLine
        self.originalText = originalText
        self.contentHash = contentHash
    }
}

public struct ProposedReplacement: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var targetID: UUID
    public var replacement: String
    public var explanation: String

    public init(
        id: UUID = UUID(),
        targetID: UUID,
        replacement: String,
        explanation: String = ""
    ) {
        self.id = id
        self.targetID = targetID
        self.replacement = replacement
        self.explanation = explanation
    }
}

public struct AIProposal: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var summary: String
    public var replacements: [ProposedReplacement]
    public var providerName: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        summary: String,
        replacements: [ProposedReplacement],
        providerName: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.summary = summary
        self.replacements = replacements
        self.providerName = providerName
        self.createdAt = createdAt
    }
}

public enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

public struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var role: ChatRole
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), role: ChatRole, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public struct ChatSession: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var projectPath: String
    public var messages: [ChatMessage]
    public var createdAt: Date
    public var updatedAt: Date
    public var archived: Bool

    public init(
        id: UUID = UUID(),
        title: String = "New Chat",
        projectPath: String,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.projectPath = projectPath
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archived = archived
    }
}

public struct AIEditHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var projectPath: String
    public var relativePath: String
    public var originalText: String
    public var replacementText: String
    public var instruction: String
    public var providerName: String
    public var createdAt: Date
    public var sessionID: UUID?

    public init(
        id: UUID = UUID(),
        projectPath: String,
        relativePath: String,
        originalText: String,
        replacementText: String,
        instruction: String,
        providerName: String,
        createdAt: Date = Date(),
        sessionID: UUID? = nil
    ) {
        self.id = id
        self.projectPath = projectPath
        self.relativePath = relativePath
        self.originalText = originalText
        self.replacementText = replacementText
        self.instruction = instruction
        self.providerName = providerName
        self.createdAt = createdAt
        self.sessionID = sessionID
    }
}
