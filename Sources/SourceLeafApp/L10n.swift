import Foundation
import SourceLeafCore

enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }

    static let appName = text("app.name")
    static let openProject = text("project.open")
    static let noProject = text("project.none")
    static let workspace = text("workspace")
    static let build = text("build")
    static let compile = text("build.compile")
    static let autoCompile = text("build.auto")
    static let source = text("panel.source")
    static let pdf = text("panel.pdf")
    static let codex = text("panel.codex")
    static let project = text("panel.project")
    static let buildLog = text("panel.buildLog")
    static let history = text("panel.history")

    static func panel(_ panel: WorkspacePanel) -> String {
        switch panel {
        case .project: project
        case .source: source
        case .pdf: pdf
        case .codex: codex
        case .buildLog: buildLog
        case .history: history
        }
    }

    static func show(_ panel: WorkspacePanel) -> String { text("action.show") + " " + self.panel(panel) }
    static func hide(_ panel: WorkspacePanel) -> String { text("action.hide") + " " + self.panel(panel) }

    static func context(_ scope: ContextScope) -> String { text("context." + scope.rawValue) }

    static func provider(_ kind: ProviderKind) -> String { text("provider." + kind.rawValue) }

    static func engine(_ engine: BuildEngine) -> String { text("engine." + engine.rawValue) }
}
