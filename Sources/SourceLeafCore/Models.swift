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
        case .source: .center
        case .pdf, .codex, .history: .trailing
        case .buildLog: .bottom
        }
    }
}

public enum ContextScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case selection
    case nearby
    case section
    case document
    case project
    case custom

    public var id: String { rawValue }
}

public enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case localCodex
    case openAI
    case openAICompatible
    case anthropic
    case gemini
    case ollama
    case lmStudio
    case customCLI

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

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ProviderKind,
        model: String = "",
        baseURL: String? = nil,
        headers: [String: String] = [:],
        command: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.model = model
        self.baseURL = baseURL
        self.headers = headers
        self.command = command
        self.enabled = enabled
    }

    public static let localCodex = ProviderProfile(
        name: "Local Codex",
        kind: .localCodex
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

    public init(
        engine: BuildEngine = .automatic,
        customCommand: String = "",
        autoBuild: Bool = true,
        debounceSeconds: Double = 1.5,
        shellEscape: Bool = false
    ) {
        self.engine = engine
        self.customCommand = customCommand
        self.autoBuild = autoBuild
        self.debounceSeconds = min(5, max(0.5, debounceSeconds))
        self.shellEscape = shellEscape
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
    public var layout: DockLayout

    public init(
        rootDocument: String? = nil,
        build: BuildConfiguration = BuildConfiguration(),
        defaultContextScope: ContextScope = .section,
        autoSave: Bool = true,
        autoSaveDelaySeconds: Double = 1,
        showSelectionButton: Bool = true,
        privateChatMode: Bool = false,
        layout: DockLayout = DockLayout()
    ) {
        self.rootDocument = rootDocument
        self.build = build
        self.defaultContextScope = defaultContextScope
        self.autoSave = autoSave
        self.autoSaveDelaySeconds = min(5, max(0.2, autoSaveDelaySeconds))
        self.showSelectionButton = showSelectionButton
        self.privateChatMode = privateChatMode
        self.layout = layout
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
        case other
    }

    public init(relativePath: String, url: URL, kind: Kind) {
        self.relativePath = relativePath
        self.url = url
        self.kind = kind
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

    public init(
        id: UUID = UUID(),
        projectPath: String,
        relativePath: String,
        originalText: String,
        replacementText: String,
        instruction: String,
        providerName: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectPath = projectPath
        self.relativePath = relativePath
        self.originalText = originalText
        self.replacementText = replacementText
        self.instruction = instruction
        self.providerName = providerName
        self.createdAt = createdAt
    }
}
