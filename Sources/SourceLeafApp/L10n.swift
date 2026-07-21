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

enum AppPresentationError: Error {
    case unknownProposalTarget
    case staticValidationFailed
    case candidateCompilationFailed
    case deletedHistoryRange
    case ambiguousHistoryRange
    case customCLIUnavailable
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
    static var image: String { text("panel.image") }
    static var pdf: String { text("panel.pdf") }
    static var codex: String { text("panel.codex") }
    static var project: String { text("panel.project") }
    static var buildLog: String { text("panel.buildLog") }
    static var history: String { text("panel.history") }

    static func panel(_ panel: WorkspacePanel) -> String {
        switch panel {
        case .project: project
        case .source: source
        case .image: image
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
    static func dockZone(_ zone: DockZone) -> String { text("dock.zone." + zone.rawValue) }

    static func validationMessage(_ issue: ValidationIssue) -> String {
        switch issue.kind {
        case .sensitiveCommandChange: return text("validation.sensitiveChange")
        case .unmatchedClosingBrace: return text("validation.unmatchedBrace")
        case .unclosedOpeningBrace: return text("validation.unclosedBrace")
        case let .unexpectedEnvironmentEnd(name):
            return String(format: text("validation.unexpectedEnd"), name)
        case let .missingEnvironmentEnd(name):
            return String(format: text("validation.missingEnd"), name)
        }
    }

    static func userMessage(for error: Error) -> String {
        if let error = error as? AppPresentationError {
            switch error {
            case .unknownProposalTarget: return text("error.unknownProposalTarget")
            case .staticValidationFailed: return text("error.staticValidationFailed")
            case .candidateCompilationFailed: return text("error.candidateCompilationFailed")
            case .deletedHistoryRange: return text("error.deletedHistoryRange")
            case .ambiguousHistoryRange: return text("error.ambiguousHistoryRange")
            case .customCLIUnavailable: return text("error.customCLIUnavailable")
            }
        }
        if let error = error as? CompilerError {
            switch error {
            case .rootDocumentMissing: return text("error.rootDocumentMissing")
            case .engineUnavailable: return text("error.engineUnavailable")
            case .invalidCustomCommand: return text("error.invalidCustomCommand")
            }
        }
        if let error = error as? SourceTargetError {
            switch error {
            case .invalidRange: return text("error.invalidRange")
            case .invalidLineRange: return text("error.invalidLineRange")
            case .pathOutsideProject: return text("error.pathOutsideProject")
            case .staleTarget: return text("error.staleTarget")
            case .replacementTargetMissing: return text("error.replacementTargetMissing")
            }
        }
        if let error = error as? AIProviderError {
            switch error {
            case let .executableNotFound(name): return String(format: text("error.executableNotFound"), name)
            case .emptyResponse: return text("error.emptyResponse")
            case .invalidResponse: return text("error.invalidAIResponse")
            case let .requestFailed(status, _): return String(format: text("error.requestFailed"), status)
            case .missingCredential: return text("error.missingCredential")
            }
        }
        if error is KeychainError { return text("error.keychain") }
        return String(format: text("error.unexpected"), (error as NSError).code)
    }
}
