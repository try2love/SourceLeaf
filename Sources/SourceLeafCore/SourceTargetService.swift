import CryptoKit
import Foundation

public enum SourceTargetError: Error, LocalizedError, Equatable {
    case invalidRange
    case invalidLineRange
    case pathOutsideProject
    case staleTarget
    case replacementTargetMissing

    public var errorDescription: String? {
        switch self {
        case .invalidRange: "The selected source range is no longer valid."
        case .invalidLineRange: "The requested line range is invalid."
        case .pathOutsideProject: "The requested file is outside the current project."
        case .staleTarget: "The source changed after the request was sent. Generate a new proposal."
        case .replacementTargetMissing: "The proposal references a target that is not attached."
        }
    }
}

public struct ParsedLineReference: Equatable, Sendable {
    public var relativePath: String?
    public var startLine: Int
    public var endLine: Int

    public init(relativePath: String?, startLine: Int, endLine: Int) {
        self.relativePath = relativePath
        self.startLine = startLine
        self.endLine = endLine
    }
}

public enum SourceTargetService {
    private static let explicitPattern = #"(?:(?<path>[A-Za-z0-9_./\-]+\.(?:tex|bib|sty|cls))\s*:)\s*(?<start>\d+)\s*(?:[-–—~至到]\s*(?<end>\d+))?"#
    private static let naturalPattern = #"(?:第\s*)?(?<start>\d+)\s*(?:[-–—~至到]\s*(?<end>\d+))?\s*行"#

    public static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func target(
        in text: String,
        relativePath: String,
        utf16Range: NSRange
    ) throws -> SourceTarget {
        guard utf16Range.location >= 0,
              utf16Range.length > 0,
              NSMaxRange(utf16Range) <= (text as NSString).length else {
            throw SourceTargetError.invalidRange
        }

        let selected = (text as NSString).substring(with: utf16Range)
        let prefix = (text as NSString).substring(to: utf16Range.location)
        let startLine = prefix.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
        let endLine = startLine + selected.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }

        return SourceTarget(
            relativePath: relativePath,
            utf16Location: utf16Range.location,
            utf16Length: utf16Range.length,
            startLine: startLine,
            endLine: endLine,
            originalText: selected,
            contentHash: hash(selected)
        )
    }

    public static func target(
        in text: String,
        relativePath: String,
        startLine: Int,
        endLine: Int
    ) throws -> SourceTarget {
        guard startLine > 0, endLine >= startLine else {
            throw SourceTargetError.invalidLineRange
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard startLine <= lines.count, endLine <= lines.count else {
            throw SourceTargetError.invalidLineRange
        }

        var location = 0
        if startLine > 1 {
            for index in 0..<(startLine - 1) {
                location += lines[index].utf16.count + 1
            }
        }

        var length = 0
        for index in (startLine - 1)...(endLine - 1) {
            length += lines[index].utf16.count
            if index < endLine - 1 { length += 1 }
        }

        return try target(
            in: text,
            relativePath: relativePath,
            utf16Range: NSRange(location: location, length: length)
        )
    }

    public static func parseLineReferences(in instruction: String) -> [ParsedLineReference] {
        var results: [ParsedLineReference] = []
        let fullRange = NSRange(instruction.startIndex..<instruction.endIndex, in: instruction)

        if let expression = try? NSRegularExpression(pattern: explicitPattern, options: [.caseInsensitive]) {
            for match in expression.matches(in: instruction, range: fullRange) {
                guard let start = capturedInt("start", match: match, source: instruction) else { continue }
                let end = capturedInt("end", match: match, source: instruction) ?? start
                let path = capturedString("path", match: match, source: instruction)
                results.append(ParsedLineReference(relativePath: path, startLine: start, endLine: end))
            }
        }

        if results.isEmpty,
           let expression = try? NSRegularExpression(pattern: naturalPattern) {
            for match in expression.matches(in: instruction, range: fullRange) {
                guard let start = capturedInt("start", match: match, source: instruction) else { continue }
                let end = capturedInt("end", match: match, source: instruction) ?? start
                results.append(ParsedLineReference(relativePath: nil, startLine: start, endLine: end))
            }
        }

        return results
    }

    public static func validatedURL(relativePath: String, projectRoot: URL) throws -> URL {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPrefix) else {
            throw SourceTargetError.pathOutsideProject
        }
        return candidate
    }

    public static func apply(
        proposal: ProposedReplacement,
        targets: [SourceTarget],
        currentText: String
    ) throws -> String {
        guard let target = targets.first(where: { $0.id == proposal.targetID }) else {
            throw SourceTargetError.replacementTargetMissing
        }

        let range = NSRange(location: target.utf16Location, length: target.utf16Length)
        guard NSMaxRange(range) <= (currentText as NSString).length else {
            throw SourceTargetError.staleTarget
        }
        let currentSelection = (currentText as NSString).substring(with: range)
        guard hash(currentSelection) == target.contentHash else {
            throw SourceTargetError.staleTarget
        }

        return (currentText as NSString).replacingCharacters(in: range, with: proposal.replacement)
    }

    public static func adjustedSelection(
        _ selection: NSRange,
        replacing range: NSRange,
        replacementUTF16Length: Int
    ) -> NSRange {
        let delta = replacementUTF16Length - range.length
        if selection.location >= NSMaxRange(range) {
            return NSRange(location: max(0, selection.location + delta), length: selection.length)
        }
        if NSMaxRange(selection) <= range.location { return selection }
        return NSRange(location: range.location + replacementUTF16Length, length: 0)
    }

    private static func capturedString(
        _ name: String,
        match: NSTextCheckingResult,
        source: String
    ) -> String? {
        let range = match.range(withName: name)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: source) else { return nil }
        return String(source[swiftRange])
    }

    private static func capturedInt(
        _ name: String,
        match: NSTextCheckingResult,
        source: String
    ) -> Int? {
        capturedString(name, match: match, source: source).flatMap(Int.init)
    }
}
