import Foundation

public enum ValidationSeverity: String, Codable, Sendable {
    case info
    case warning
    case error
}

public enum ValidationIssueKind: Equatable, Sendable {
    case sensitiveCommandChange
    case unmatchedClosingBrace
    case unclosedOpeningBrace
    case unexpectedEnvironmentEnd(String)
    case missingEnvironmentEnd(String)
}

public struct ValidationIssue: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var severity: ValidationSeverity
    public var kind: ValidationIssueKind
    public var message: String
    public var line: Int?

    public init(severity: ValidationSeverity, kind: ValidationIssueKind, message: String, line: Int? = nil) {
        self.severity = severity
        self.kind = kind
        self.message = message
        self.line = line
    }
}

public struct LaTeXValidationResult: Equatable, Sendable {
    public var issues: [ValidationIssue]
    public var sensitiveChanges: [String]

    public var hasErrors: Bool { issues.contains { $0.severity == .error } }

    public init(issues: [ValidationIssue], sensitiveChanges: [String]) {
        self.issues = issues
        self.sensitiveChanges = sensitiveChanges
    }
}

public enum LaTeXValidator {
    private static let environmentPattern = #"\\(begin|end)\s*\{([^}]+)\}"#
    private static let sensitivePattern = #"\\(?:cite\w*|ref|pageref|eqref|label|begin|end)\s*(?:\[[^\]]*\])?\s*\{[^}]+\}"#

    public static func validate(original: String, replacement: String) -> LaTeXValidationResult {
        var issues = validateStructure(replacement)
        let originalSensitive = tokens(in: original, pattern: sensitivePattern)
        let replacementSensitive = tokens(in: replacement, pattern: sensitivePattern)
        let removed = originalSensitive.subtracting(replacementSensitive).sorted()
        let added = replacementSensitive.subtracting(originalSensitive).sorted()
        let sensitiveChanges = removed.map { "Removed: \($0)" } + added.map { "Added: \($0)" }

        if !sensitiveChanges.isEmpty {
            issues.append(ValidationIssue(
                severity: .warning,
                kind: .sensitiveCommandChange,
                message: "The proposal changes citation, reference, label, or environment commands."
            ))
        }

        return LaTeXValidationResult(issues: issues, sensitiveChanges: sensitiveChanges)
    }

    public static func validateStructure(_ source: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var braceStack: [(line: Int, character: Character)] = []
        var line = 1
        var escaped = false
        var inComment = false

        for character in source {
            if character == "\n" {
                line += 1
                inComment = false
                escaped = false
                continue
            }
            if inComment { continue }
            if character == "%", !escaped {
                inComment = true
                continue
            }
            if character == "\\" {
                escaped.toggle()
                continue
            }
            if character == "{", !escaped {
                braceStack.append((line, character))
            } else if character == "}", !escaped {
                if braceStack.isEmpty {
                    issues.append(ValidationIssue(severity: .error, kind: .unmatchedClosingBrace, message: "Unmatched closing brace.", line: line))
                } else {
                    braceStack.removeLast()
                }
            }
            escaped = false
        }

        for item in braceStack {
            issues.append(ValidationIssue(severity: .error, kind: .unclosedOpeningBrace, message: "Unclosed opening brace.", line: item.line))
        }

        var environments: [(name: String, line: Int)] = []
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)
        if let expression = try? NSRegularExpression(pattern: environmentPattern) {
            for match in expression.matches(in: source, range: fullRange) {
                guard match.numberOfRanges == 3 else { continue }
                let command = nsSource.substring(with: match.range(at: 1))
                let name = nsSource.substring(with: match.range(at: 2))
                let prefix = nsSource.substring(to: match.range.location)
                let commandLine = prefix.reduce(into: 1) { count, character in
                    if character == "\n" { count += 1 }
                }

                if command == "begin" {
                    environments.append((name, commandLine))
                } else if environments.last?.name == name {
                    environments.removeLast()
                } else {
                    issues.append(ValidationIssue(
                        severity: .error,
                        kind: .unexpectedEnvironmentEnd(name),
                        message: "Unexpected \\end{\(name)}.",
                        line: commandLine
                    ))
                }
            }
        }

        for environment in environments {
            issues.append(ValidationIssue(
                severity: .error,
                kind: .missingEnvironmentEnd(environment.name),
                message: "Missing \\end{\(environment.name)}.",
                line: environment.line
            ))
        }

        return issues
    }

    private static func tokens(in text: String, pattern: String) -> Set<String> {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return Set(expression.matches(in: text, range: range).map { nsText.substring(with: $0.range) })
    }
}
