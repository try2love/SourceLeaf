import Foundation
import SourceLeafCore

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }
    var localeIdentifier: String {
        switch self {
        case .system: Locale.autoupdatingCurrent.identifier
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }
    var isChinese: Bool {
        switch self {
        case .simplifiedChinese: true
        case .english: false
        case .system: Locale.autoupdatingCurrent.language.languageCode?.identifier == "zh"
        }
    }
}

enum L10n {
    static let languageDefaultsKey = "SourceLeaf.appLanguage"

    static var selectedLanguage: AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: languageDefaultsKey),
              let language = AppLanguage(rawValue: raw) else { return .system }
        return language
    }

    static func text(_ key: String) -> String {
        let language = selectedLanguage
        guard language != .system,
              let path = Bundle.module.path(forResource: language.localeIdentifier, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return NSLocalizedString(key, bundle: .module, comment: "")
        }
        return NSLocalizedString(key, bundle: localizedBundle, comment: "")
    }

    static var appName: String { text("app.name") }
    static var openProject: String { text("project.open") }
    static var noProject: String { text("project.none") }
    static var workspace: String { text("workspace") }
    static var build: String { text("build") }
    static var compile: String { text("build.compile") }
    static var autoCompile: String { text("build.auto") }
    static var source: String { text("panel.source") }
    static var pdf: String { text("panel.pdf") }
    static var codex: String { text("panel.codex") }
    static var project: String { text("panel.project") }
    static var buildLog: String { text("panel.buildLog") }
    static var history: String { text("panel.history") }

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
