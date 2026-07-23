import Foundation

public enum LaTeXEditCommand: String, CaseIterable, Sendable {
    case bold, italic, underline, emphasis
    case toggleComment
    case indentLines, outdentLines
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
        case .toggleComment: return toggledLineComment(nsSource, selection)
        case .indentLines: return shiftedLines(nsSource, selection, direction: .indent)
        case .outdentLines: return shiftedLines(nsSource, selection, direction: .outdent)
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

    private struct TextDelta {
        var location: Int
        var removedLength: Int
        var insertedLength: Int
    }

    private enum LineShiftDirection {
        case indent
        case outdent
    }

    private static func shiftedLines(
        _ source: NSString,
        _ selection: NSRange,
        direction: LineShiftDirection
    ) -> LaTeXSourceEdit {
        if source.length == 0 || selection.length == 0 {
            switch direction {
            case .indent:
                return LaTeXSourceEdit(
                    replacementRange: selection,
                    replacement: "  ",
                    resultingSelection: NSRange(location: selection.location + 2, length: 0)
                )
            case .outdent:
                let lineRange = source.length == 0
                    ? NSRange(location: 0, length: 0)
                    : selectedLineRange(in: source, selection: selection)
                guard let removal = leadingIndentRemoval(in: source, lineRange: lineRange) else {
                    return LaTeXSourceEdit(replacementRange: selection, replacement: "", resultingSelection: selection)
                }
                let line = source.substring(with: lineRange) as NSString
                let localRemoval = removal.location - lineRange.location
                let replacement = line.substring(to: localRemoval)
                    + line.substring(from: localRemoval + removal.length)
                let caret = max(lineRange.location, selection.location - removal.length)
                return LaTeXSourceEdit(
                    replacementRange: lineRange,
                    replacement: replacement,
                    resultingSelection: NSRange(location: caret, length: 0)
                )
            }
        }

        let replacementRange = selectedLineRange(in: source, selection: selection)
        let lineRanges = lineRanges(in: source, covering: replacementRange)
        var replacement = ""

        for lineRange in lineRanges {
            let line = source.substring(with: lineRange) as NSString
            switch direction {
            case .indent:
                if shouldIndentLine(in: source, lineRange: lineRange) {
                    replacement += "  " + (line as String)
                } else {
                    replacement += line as String
                }
            case .outdent:
                if let removal = leadingIndentRemoval(in: source, lineRange: lineRange) {
                    let localRemoval = removal.location - lineRange.location
                    replacement += line.substring(to: localRemoval)
                        + line.substring(from: localRemoval + removal.length)
                } else {
                    replacement += line as String
                }
            }
        }

        return LaTeXSourceEdit(
            replacementRange: replacementRange,
            replacement: replacement,
            resultingSelection: NSRange(location: replacementRange.location, length: (replacement as NSString).length)
        )
    }

    private static func toggledLineComment(_ source: NSString, _ selection: NSRange) -> LaTeXSourceEdit {
        if source.length == 0 {
            return LaTeXSourceEdit(
                replacementRange: NSRange(location: 0, length: 0),
                replacement: "% ",
                resultingSelection: NSRange(location: 2, length: 0)
            )
        }

        let replacementRange = selectedLineRange(in: source, selection: selection)
        let lineRanges = lineRanges(in: source, covering: replacementRange)
        let nonBlankLineRanges = lineRanges.filter { lineRange in
            let contents = lineContents(in: source, lineRange: lineRange)
            return !source.substring(with: contents).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let shouldUncomment = !nonBlankLineRanges.isEmpty && nonBlankLineRanges.allSatisfy {
            commentMarkerRange(in: source, lineRange: $0) != nil
        }

        var replacement = ""
        var deltas: [TextDelta] = []
        for lineRange in lineRanges {
            if shouldUncomment, let marker = commentMarkerRange(in: source, lineRange: lineRange) {
                let line = source.substring(with: lineRange) as NSString
                let localMarker = marker.location - lineRange.location
                let before = line.substring(with: NSRange(location: 0, length: localMarker))
                let afterLocation = localMarker + marker.length
                let after = line.substring(with: NSRange(location: afterLocation, length: line.length - afterLocation))
                replacement += before + after
                deltas.append(TextDelta(location: marker.location, removedLength: marker.length, insertedLength: 0))
            } else if !shouldUncomment, shouldCommentLine(in: source, lineRange: lineRange) {
                let line = source.substring(with: lineRange) as NSString
                let insertLocation = commentInsertionLocation(in: source, lineRange: lineRange)
                let localInsert = insertLocation - lineRange.location
                let before = line.substring(with: NSRange(location: 0, length: localInsert))
                let after = line.substring(with: NSRange(location: localInsert, length: line.length - localInsert))
                replacement += before + "% " + after
                deltas.append(TextDelta(location: insertLocation, removedLength: 0, insertedLength: 2))
            } else {
                replacement += source.substring(with: lineRange)
            }
        }

        let resultingSelection: NSRange
        if selection.length == 0 {
            resultingSelection = NSRange(
                location: transformedLocation(selection.location, applying: deltas),
                length: 0
            )
        } else {
            resultingSelection = NSRange(
                location: replacementRange.location,
                length: (replacement as NSString).length
            )
        }
        return LaTeXSourceEdit(
            replacementRange: replacementRange,
            replacement: replacement,
            resultingSelection: resultingSelection
        )
    }

    private static func selectedLineRange(in source: NSString, selection: NSRange) -> NSRange {
        let startLocation = min(selection.location, source.length)
        let endLocation: Int
        if selection.length == 0 {
            endLocation = startLocation
        } else {
            let rawEnd = min(NSMaxRange(selection), source.length)
            endLocation = rawEnd > selection.location && rawEnd > 0 && source.character(at: rawEnd - 1) == 10
                ? rawEnd - 1
                : rawEnd
        }
        let startLine = source.lineRange(for: NSRange(location: min(startLocation, max(0, source.length - 1)), length: 0))
        let endLine = source.lineRange(for: NSRange(location: min(endLocation, max(0, source.length - 1)), length: 0))
        return NSUnionRange(startLine, endLine)
    }

    private static func lineRanges(in source: NSString, covering range: NSRange) -> [NSRange] {
        guard range.length > 0 else { return [source.lineRange(for: range)] }
        var ranges: [NSRange] = []
        var location = range.location
        let end = NSMaxRange(range)
        while location < end {
            let lineRange = source.lineRange(for: NSRange(location: min(location, max(0, source.length - 1)), length: 0))
            ranges.append(NSIntersectionRange(lineRange, range).length == lineRange.length ? lineRange : lineRange)
            let next = NSMaxRange(lineRange)
            guard next > location else { break }
            location = next
        }
        return ranges
    }

    private static func lineContents(in source: NSString, lineRange: NSRange) -> NSRange {
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        source.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: lineRange)
        return NSRange(location: lineStart, length: contentsEnd - lineStart)
    }

    private static func shouldCommentLine(in source: NSString, lineRange: NSRange) -> Bool {
        let contents = lineContents(in: source, lineRange: lineRange)
        return !source.substring(with: contents).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func shouldIndentLine(in source: NSString, lineRange: NSRange) -> Bool {
        let contents = lineContents(in: source, lineRange: lineRange)
        return !source.substring(with: contents).isEmpty
    }

    private static func leadingIndentRemoval(in source: NSString, lineRange: NSRange) -> NSRange? {
        let contents = lineContents(in: source, lineRange: lineRange)
        guard contents.length > 0 else { return nil }
        let first = source.character(at: contents.location)
        if first == 9 {
            return NSRange(location: contents.location, length: 1)
        }
        guard first == 32 else { return nil }
        if contents.length >= 2, source.character(at: contents.location + 1) == 32 {
            return NSRange(location: contents.location, length: 2)
        }
        return NSRange(location: contents.location, length: 1)
    }

    private static func commentInsertionLocation(in source: NSString, lineRange: NSRange) -> Int {
        let contents = lineContents(in: source, lineRange: lineRange)
        var location = contents.location
        while location < NSMaxRange(contents) {
            let character = source.character(at: location)
            if character != 32 && character != 9 { break }
            location += 1
        }
        return location
    }

    private static func commentMarkerRange(in source: NSString, lineRange: NSRange) -> NSRange? {
        let insertion = commentInsertionLocation(in: source, lineRange: lineRange)
        let contents = lineContents(in: source, lineRange: lineRange)
        guard insertion < NSMaxRange(contents), source.character(at: insertion) == 37 else { return nil }
        let hasFollowingSpace = insertion + 1 < NSMaxRange(contents) && source.character(at: insertion + 1) == 32
        return NSRange(location: insertion, length: hasFollowingSpace ? 2 : 1)
    }

    private static func transformedLocation(_ location: Int, applying deltas: [TextDelta]) -> Int {
        var result = location
        for delta in deltas.sorted(by: { $0.location < $1.location }) {
            if delta.removedLength == 0 {
                if delta.location <= location { result += delta.insertedLength }
            } else if delta.location < location {
                result -= min(delta.removedLength, location - delta.location)
            }
        }
        return max(0, result)
    }
}
