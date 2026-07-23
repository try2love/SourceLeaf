import Foundation

public enum LaTeXEditCommand: String, CaseIterable, Sendable {
    case bold, italic, underline, emphasis
    case tiny, scriptsize, footnotesize, small, normalsize, large, largeUpper, largeAllCaps, huge, hugeUpper
    case section, subsection, subsubsection, paragraph
    case inlineMath, displayMath, equation, fraction, superscript, subscriptText
    case itemize, enumerate, table, figure, cite, reference, label, url
}

public struct LaTeXEditRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let command: LaTeXEditCommand
    public let argument: String?

    public init(id: UUID = UUID(), command: LaTeXEditCommand, argument: String? = nil) {
        self.id = id
        self.command = command
        self.argument = argument
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
        selection proposedSelection: NSRange,
        argument: String? = nil
    ) -> LaTeXSourceEdit {
        let sourceLength = (source as NSString).length
        let selection = validRange(proposedSelection, sourceLength: sourceLength)
        let nsSource = source as NSString
        let selected = nsSource.substring(with: selection)

        switch command {
        case .bold: return wrapped(nsSource, selection, selected, prefix: "\\textbf{", suffix: "}", placeholder: "text")
        case .italic: return wrapped(nsSource, selection, selected, prefix: "\\textit{", suffix: "}", placeholder: "text")
        case .underline: return wrapped(nsSource, selection, selected, prefix: "\\underline{", suffix: "}", placeholder: "text")
        case .emphasis: return wrapped(nsSource, selection, selected, prefix: "\\emph{", suffix: "}", placeholder: "text")
        case .tiny: return sized(nsSource, selection, selected, command: "tiny")
        case .scriptsize: return sized(nsSource, selection, selected, command: "scriptsize")
        case .footnotesize: return sized(nsSource, selection, selected, command: "footnotesize")
        case .small: return sized(nsSource, selection, selected, command: "small")
        case .normalsize: return sized(nsSource, selection, selected, command: "normalsize")
        case .large: return sized(nsSource, selection, selected, command: "large")
        case .largeUpper: return sized(nsSource, selection, selected, command: "Large")
        case .largeAllCaps: return sized(nsSource, selection, selected, command: "LARGE")
        case .huge: return sized(nsSource, selection, selected, command: "huge")
        case .hugeUpper: return sized(nsSource, selection, selected, command: "Huge")
        case .section: return wrapped(nsSource, selection, selected, prefix: "\\section{", suffix: "}", placeholder: "Title")
        case .subsection: return wrapped(nsSource, selection, selected, prefix: "\\subsection{", suffix: "}", placeholder: "Title")
        case .subsubsection: return wrapped(nsSource, selection, selected, prefix: "\\subsubsection{", suffix: "}", placeholder: "Title")
        case .paragraph: return wrapped(nsSource, selection, selected, prefix: "\\paragraph{", suffix: "}", placeholder: "Title")
        case .inlineMath: return wrapped(nsSource, selection, selected, prefix: "$", suffix: "$", placeholder: "formula")
        case .displayMath: return wrapped(nsSource, selection, selected, prefix: "\\[\n", suffix: "\n\\]", placeholder: "formula")
        case .equation: return wrapped(nsSource, selection, selected, prefix: "\\begin{equation}\n", suffix: "\n\\end{equation}", placeholder: "formula")
        case .fraction:
            let numerator = selected.isEmpty ? "numerator" : selected
            let replacement = "\\frac{\(numerator)}{denominator}"
            let target = selected.isEmpty
                ? NSRange(location: selection.location + 6, length: (numerator as NSString).length)
                : NSRange(location: selection.location + 8 + (numerator as NSString).length, length: 11)
            return LaTeXSourceEdit(replacementRange: selection, replacement: replacement, resultingSelection: target)
        case .superscript: return wrapped(nsSource, selection, selected, prefix: "^{", suffix: "}", placeholder: "exponent")
        case .subscriptText: return wrapped(nsSource, selection, selected, prefix: "_{", suffix: "}", placeholder: "index")
        case .itemize: return list(nsSource, selection, selected, environment: "itemize")
        case .enumerate: return list(nsSource, selection, selected, environment: "enumerate")
        case .table: return template(selection, template: "\\begin{table}[htbp]\n  \\centering\n  \\caption{Caption}\n  \\label{tab:label}\n  \\begin{tabular}{ll}\n    \\hline\n    Column 1 & Column 2 \\\\\n    \\hline\n    Value 1 & Value 2 \\\\\n    \\hline\n  \\end{tabular}\n\\end{table}", target: "Caption")
        case .figure:
            let explicitPath = argument?.trimmingCharacters(in: .whitespacesAndNewlines)
            let path = explicitPath?.isEmpty == false ? explicitPath! : (selected.isEmpty ? "figures/image.png" : selected)
            let target = selected.isEmpty && explicitPath == nil ? path : "Caption"
            return template(selection, template: "\\begin{figure}[htbp]\n  \\centering\n  \\includegraphics[width=\\linewidth]{\(path)}\n  \\caption{Caption}\n  \\label{fig:label}\n\\end{figure}", target: target)
        case .cite: return wrapped(nsSource, selection, selected, prefix: "\\cite{", suffix: "}", placeholder: "citation-key")
        case .reference: return wrapped(nsSource, selection, selected, prefix: "\\ref{", suffix: "}", placeholder: "label")
        case .label: return wrapped(nsSource, selection, selected, prefix: "\\label{", suffix: "}", placeholder: "label")
        case .url: return wrapped(nsSource, selection, selected, prefix: "\\url{", suffix: "}", placeholder: "https://")
        }
    }

    private static func validRange(_ range: NSRange, sourceLength: Int) -> NSRange {
        let location = min(max(0, range.location), sourceLength)
        let length = min(max(0, range.length), sourceLength - location)
        return NSRange(location: location, length: length)
    }

    private static func wrapped(
        _ source: NSString,
        _ selection: NSRange,
        _ selected: String,
        prefix: String,
        suffix: String,
        placeholder: String
    ) -> LaTeXSourceEdit {
        let prefixLength = (prefix as NSString).length
        let suffixLength = (suffix as NSString).length
        if !selected.isEmpty {
            if selected.hasPrefix(prefix), selected.hasSuffix(suffix) {
                let innerRange = NSRange(
                    location: prefixLength,
                    length: (selected as NSString).length - prefixLength - suffixLength
                )
                let inner = (selected as NSString).substring(with: innerRange)
                return LaTeXSourceEdit(
                    replacementRange: selection,
                    replacement: inner,
                    resultingSelection: NSRange(location: selection.location, length: innerRange.length)
                )
            }
            let wrapperLocation = selection.location - prefixLength
            let wrapperLength = prefixLength + selection.length + suffixLength
            if wrapperLocation >= 0,
               NSMaxRange(NSRange(location: wrapperLocation, length: wrapperLength)) <= source.length,
               source.substring(with: NSRange(location: wrapperLocation, length: prefixLength)) == prefix,
               source.substring(with: NSRange(location: NSMaxRange(selection), length: suffixLength)) == suffix {
                return LaTeXSourceEdit(
                    replacementRange: NSRange(location: wrapperLocation, length: wrapperLength),
                    replacement: selected,
                    resultingSelection: NSRange(location: wrapperLocation, length: selection.length)
                )
            }
        }
        let content = selected.isEmpty ? placeholder : selected
        let replacement = prefix + content + suffix
        let result = NSRange(
            location: selection.location + prefixLength,
            length: (content as NSString).length
        )
        return LaTeXSourceEdit(replacementRange: selection, replacement: replacement, resultingSelection: result)
    }

    private static func sized(_ source: NSString, _ selection: NSRange, _ selected: String, command: String) -> LaTeXSourceEdit {
        wrapped(source, selection, selected, prefix: "{\\\(command) ", suffix: "}", placeholder: "text")
    }

    private static func list(_ source: NSString, _ selection: NSRange, _ selected: String, environment: String) -> LaTeXSourceEdit {
        let items = selected.isEmpty
            ? "Item"
            : selected.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).joined(separator: "\n  \\item ")
        let prefix = "\\begin{\(environment)}\n  \\item "
        let suffix = "\n\\end{\(environment)}"
        return wrapped(source, selection, items, prefix: prefix, suffix: suffix, placeholder: "Item")
    }

    private static func template(_ selection: NSRange, template: String, target: String) -> LaTeXSourceEdit {
        let targetRange = (template as NSString).range(of: target)
        return LaTeXSourceEdit(
            replacementRange: selection,
            replacement: template,
            resultingSelection: NSRange(location: selection.location + targetRange.location, length: targetRange.length)
        )
    }
}
