import Foundation

public enum BuildPhase: String, Equatable, Sendable {
    case idle
    case preparingResources
    case typesetting
    case bibliography
    case renderingPDF
    case finished
}

public struct BuildLogSummary: Equatable, Sendable {
    public var warningCount: Int
    public var errorCount: Int
    public var downloadCount: Int
    public var phase: BuildPhase

    public init(log: String) {
        var warningCount = 0
        var errorCount = 0
        var downloadCount = 0
        var phase: BuildPhase = .idle

        for rawLine in log.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("warning:") { warningCount += 1 }
            if line.hasPrefix("error:") { errorCount += 1 }
            if line.hasPrefix("note: downloading") {
                downloadCount += 1
                phase = .preparingResources
            } else if line.localizedCaseInsensitiveContains("running bibtex") ||
                        line.localizedCaseInsensitiveContains("running biber") {
                phase = .bibliography
            } else if line.localizedCaseInsensitiveContains("running xdvipdfmx") {
                phase = .renderingPDF
            } else if line.localizedCaseInsensitiveContains("running tex") ||
                        line.localizedCaseInsensitiveContains("rerunning tex") {
                phase = .typesetting
            } else if line.hasPrefix("note: Writing") && line.contains(".pdf") {
                phase = .finished
            }
        }

        self.warningCount = warningCount
        self.errorCount = errorCount
        self.downloadCount = downloadCount
        self.phase = phase
    }
}
