import Foundation

public enum LaTeXEditCommand: String, CaseIterable, Sendable {
    case bold, italic, underline, emphasis
    case tiny, scriptsize, footnotesize, small, normalsize, large, largeUpper, largeAllCaps, huge, hugeUpper
    case section, subsection, subsubsection, paragraph
    case inlineMath, displayMath, equation, fraction, superscript, subscriptText
    case itemize, enumerate, cite, reference, label, url
}

public struct LaTeXEditRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let command: LaTeXEditCommand

    public init(id: UUID = UUID(), command: LaTeXEditCommand) {
        self.id = id
        self.command = command
    }
}

public struct LaTeXSourceEdit: Equatable, Sendable {
    public var replacementRange: NSRange
    public var replacement: String
    public var resultingSelection: NSRange

    public init(replacementRange: NSRange, replacement: String, resultingSelection: NSRange) {
        self.replacementRange = replacementRange
        self.replacement = replacement
        self.resultingSelection = resultingSelection
    }
}

public enum LaTeXSourceFormatter {
    public static func edit(
        command: LaTeXEditCommand,
        source: String,
        selection proposedSelection: NSRange
    ) -> LaTeXSourceEdit {
        let sourceLength = (source as NSString).length
        let selection = validRange(proposedSelection, sourceLength: sourceLength)
        let selected = (source as NSString).substring(with: selection)

        switch command {
        case .bold: return wrapped(selection, selected, prefix: "\\textbf{", suffix: "}", placeholder: "text")
        case .italic: return wrapped(selection, selected, prefix: "\\textit{", suffix: "}", placeholder: "text")
        case .underline: return wrapped(selection, selected, prefix: "\\underline{", suffix: "}", placeholder: "text")
        case .emphasis: return wrapped(selection, selected, prefix: "\\emph{", suffix: "}", placeholder: "text")
        case .tiny: return sized(selection, selected, command: "tiny")
        case .scriptsize: return sized(selection, selected, command: "scriptsize")
        case .footnotesize: return sized(selection, selected, command: "footnotesize")
        case .small: return sized(selection, selected, command: "small")
        case .normalsize: return sized(selection, selected, command: "normalsize")
        case .large: return sized(selection, selected, command: "large")
        case .largeUpper: return sized(selection, selected, command: "Large")
        case .largeAllCaps: return sized(selection, selected, command: "LARGE")
        case .huge: return sized(selection, selected, command: "huge")
        case .hugeUpper: return sized(selection, selected, command: "Huge")
        case .section: return wrapped(selection, selected, prefix: "\\section{", suffix: "}", placeholder: "Title")
        case .subsection: return wrapped(selection, selected, prefix: "\\subsection{", suffix: "}", placeholder: "Title")
        case .subsubsection: return wrapped(selection, selected, prefix: "\\subsubsection{", suffix: "}", placeholder: "Title")
        case .paragraph: return wrapped(selection, selected, prefix: "\\paragraph{", suffix: "}", placeholder: "Title")
        case .inlineMath: return wrapped(selection, selected, prefix: "$", suffix: "$", placeholder: "formula")
        case .displayMath: return wrapped(selection, selected, prefix: "\\[\n", suffix: "\n\\]", placeholder: "formula")
        case .equation: return wrapped(selection, selected, prefix: "\\begin{equation}\n", suffix: "\n\\end{equation}", placeholder: "formula")
        case .fraction:
            let numerator = selected.isEmpty ? "numerator" : selected
            let replacement = "\\frac{\(numerator)}{denominator}"
            let target = selected.isEmpty
                ? NSRange(location: selection.location + 6, length: (numerator as NSString).length)
                : NSRange(location: selection.location + 8 + (numerator as NSString).length, length: 11)
            return LaTeXSourceEdit(replacementRange: selection, replacement: replacement, resultingSelection: target)
        case .superscript: return wrapped(selection, selected, prefix: "^{", suffix: "}", placeholder: "exponent")
        case .subscriptText: return wrapped(selection, selected, prefix: "_{", suffix: "}", placeholder: "index")
        case .itemize: return list(selection, selected, environment: "itemize")
        case .enumerate: return list(selection, selected, environment: "enumerate")
        case .cite: return wrapped(selection, selected, prefix: "\\cite{", suffix: "}", placeholder: "citation-key")
        case .reference: return wrapped(selection, selected, prefix: "\\ref{", suffix: "}", placeholder: "label")
        case .label: return wrapped(selection, selected, prefix: "\\label{", suffix: "}", placeholder: "label")
        case .url: return wrapped(selection, selected, prefix: "\\url{", suffix: "}", placeholder: "https://")
        }
    }

    private static func validRange(_ range: NSRange, sourceLength: Int) -> NSRange {
        let location = min(max(0, range.location), sourceLength)
        let length = min(max(0, range.length), sourceLength - location)
        return NSRange(location: location, length: length)
    }

    private static func wrapped(
        _ selection: NSRange,
        _ selected: String,
        prefix: String,
        suffix: String,
        placeholder: String
    ) -> LaTeXSourceEdit {
        let content = selected.isEmpty ? placeholder : selected
        let replacement = prefix + content + suffix
        let result = NSRange(
            location: selection.location + (prefix as NSString).length,
            length: (content as NSString).length
        )
        return LaTeXSourceEdit(replacementRange: selection, replacement: replacement, resultingSelection: result)
    }

    private static func sized(_ selection: NSRange, _ selected: String, command: String) -> LaTeXSourceEdit {
        wrapped(selection, selected, prefix: "{\\\(command) ", suffix: "}", placeholder: "text")
    }

    private static func list(_ selection: NSRange, _ selected: String, environment: String) -> LaTeXSourceEdit {
        let items = selected.isEmpty
            ? "Item"
            : selected.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).joined(separator: "\n  \\item ")
        let prefix = "\\begin{\(environment)}\n  \\item "
        let suffix = "\n\\end{\(environment)}"
        return wrapped(selection, items, prefix: prefix, suffix: suffix, placeholder: "Item")
    }
}
