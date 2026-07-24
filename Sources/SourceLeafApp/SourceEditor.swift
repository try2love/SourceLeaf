import AppKit
import QuartzCore
import SwiftUI
import SourceLeafCore

enum SourceTextSynchronization {
    static func shouldApplyExternalText(
        incoming: String,
        nativeText: String,
        lastLocallyEmittedText: String?
    ) -> Bool {
        guard incoming != nativeText else { return false }
        // SwiftUI may deliver an older binding value after NSTextView has
        // already accepted another keystroke. Never let that echo replace the
        // newer native buffer; a genuine external edit has no local marker.
        return lastLocallyEmittedText != nativeText
    }
}

struct LaTeXCompletionCandidate: Equatable, Sendable {
    var insertion: String
    var category: String
    var detail: String
}

struct LaTeXCompletionContext: Equatable, Sendable {
    var labels: [String] = []
    var citations: [String] = []
    var graphicsFiles: [String] = []
    var projectFiles: [String] = []

    init(index: ProjectIndex? = nil, projectFiles: [String] = []) {
        labels = index?.labels.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending } ?? []
        citations = index?.citations ?? []
        graphicsFiles = index?.includedFiles ?? []
        self.projectFiles = projectFiles
    }
}

enum LaTeXCompletionEngine {
    static let builtInCandidates: [LaTeXCompletionCandidate] = [
        .init(insertion: #"\usepackage{}"#, category: "pkg", detail: "Load a package"),
        .init(insertion: #"\usepackage[]{}"#, category: "pkg", detail: "Load a package with options"),
        .init(insertion: #"\documentclass{}"#, category: "cls", detail: "Set the document class"),
        .init(insertion: #"\title{}"#, category: "meta", detail: "Paper title"),
        .init(insertion: #"\author{}"#, category: "meta", detail: "Author list"),
        .init(insertion: #"\date{}"#, category: "meta", detail: "Date"),
        .init(insertion: #"\maketitle"#, category: "meta", detail: "Typeset title block"),
        .init(insertion: #"\thanks{}"#, category: "meta", detail: "Author note"),
        .init(insertion: #"\begin{}"#, category: "env", detail: "Begin an environment"),
        .init(insertion: #"\end{}"#, category: "env", detail: "End an environment"),
        .init(insertion: #"\begin{document}"#, category: "env", detail: "Begin document body"),
        .init(insertion: #"\begin{abstract}"#, category: "env", detail: "Begin abstract"),
        .init(insertion: #"\begin{figure}"#, category: "env", detail: "Begin a figure environment"),
        .init(insertion: #"\begin{figure*}"#, category: "env", detail: "Begin a two-column figure"),
        .init(insertion: #"\begin{table}"#, category: "env", detail: "Begin a table environment"),
        .init(insertion: #"\begin{table*}"#, category: "env", detail: "Begin a two-column table"),
        .init(insertion: #"\begin{equation}"#, category: "env", detail: "Begin an equation environment"),
        .init(insertion: #"\begin{equation*}"#, category: "env", detail: "Begin an unnumbered equation"),
        .init(insertion: #"\begin{align}"#, category: "env", detail: "Begin aligned equations"),
        .init(insertion: #"\begin{align*}"#, category: "env", detail: "Begin unnumbered aligned equations"),
        .init(insertion: #"\begin{tabular}{}"#, category: "env", detail: "Begin tabular data"),
        .init(insertion: #"\begin{minipage}{}"#, category: "env", detail: "Begin a minipage"),
        .init(insertion: #"\begin{itemize}"#, category: "env", detail: "Begin an itemized list"),
        .init(insertion: #"\begin{enumerate}"#, category: "env", detail: "Begin an enumerated list"),
        .init(insertion: #"\begin{description}"#, category: "env", detail: "Begin a description list"),
        .init(insertion: #"\item"#, category: "cmd", detail: "Add a list item"),
        .init(insertion: #"\item[]"#, category: "cmd", detail: "Add a labeled list item"),
        .init(insertion: #"\section{}"#, category: "sec", detail: "Section heading"),
        .init(insertion: #"\subsection{}"#, category: "sec", detail: "Subsection heading"),
        .init(insertion: #"\subsubsection{}"#, category: "sec", detail: "Subsubsection heading"),
        .init(insertion: #"\paragraph{}"#, category: "sec", detail: "Paragraph heading"),
        .init(insertion: #"\textbf{}"#, category: "fmt", detail: "Bold text"),
        .init(insertion: #"\textit{}"#, category: "fmt", detail: "Italic text"),
        .init(insertion: #"\emph{}"#, category: "fmt", detail: "Emphasized text"),
        .init(insertion: #"\underline{}"#, category: "fmt", detail: "Underline text"),
        .init(insertion: #"\texttt{}"#, category: "fmt", detail: "Monospace text"),
        .init(insertion: #"\textsc{}"#, category: "fmt", detail: "Small caps text"),
        .init(insertion: #"\footnote{}"#, category: "fmt", detail: "Footnote"),
        .init(insertion: #"\small"#, category: "fmt", detail: "Small font size"),
        .init(insertion: #"\normalsize"#, category: "fmt", detail: "Normal font size"),
        .init(insertion: #"\large"#, category: "fmt", detail: "Large font size"),
        .init(insertion: #"\cite{}"#, category: "ref", detail: "Citation"),
        .init(insertion: #"\citep{}"#, category: "ref", detail: "Parenthetical citation"),
        .init(insertion: #"\citet{}"#, category: "ref", detail: "Textual citation"),
        .init(insertion: #"\ref{}"#, category: "ref", detail: "Reference a label"),
        .init(insertion: #"\autoref{}"#, category: "ref", detail: "Automatic reference"),
        .init(insertion: #"\eqref{}"#, category: "ref", detail: "Equation reference"),
        .init(insertion: #"\label{}"#, category: "ref", detail: "Create a label"),
        .init(insertion: #"\url{}"#, category: "cmd", detail: "URL"),
        .init(insertion: #"\href{}{}"#, category: "cmd", detail: "Hyperlink"),
        .init(insertion: #"\bibliographystyle{}"#, category: "bib", detail: "Bibliography style"),
        .init(insertion: #"\bibliography{}"#, category: "bib", detail: "BibTeX bibliography"),
        .init(insertion: #"\addbibresource{}"#, category: "bib", detail: "biblatex resource"),
        .init(insertion: #"\printbibliography"#, category: "bib", detail: "Print bibliography"),
        .init(insertion: #"\includegraphics[]{}"#, category: "fig", detail: "Insert a graphic"),
        .init(insertion: #"\caption{}"#, category: "fig", detail: "Caption"),
        .init(insertion: #"\subcaption{}"#, category: "fig", detail: "Subcaption"),
        .init(insertion: #"\centering"#, category: "cmd", detail: "Center content"),
        .init(insertion: #"\frac{}{}"#, category: "math", detail: "Fraction"),
        .init(insertion: #"\sqrt{}"#, category: "math", detail: "Square root"),
        .init(insertion: #"\sum"#, category: "math", detail: "Summation"),
        .init(insertion: #"\prod"#, category: "math", detail: "Product"),
        .init(insertion: #"\int"#, category: "math", detail: "Integral"),
        .init(insertion: #"\lim"#, category: "math", detail: "Limit"),
        .init(insertion: #"\infty"#, category: "math", detail: "Infinity"),
        .init(insertion: #"\rightarrow"#, category: "math", detail: "Right arrow"),
        .init(insertion: #"\left"#, category: "math", detail: "Left delimiter"),
        .init(insertion: #"\right"#, category: "math", detail: "Right delimiter"),
        .init(insertion: #"\mathbf{}"#, category: "math", detail: "Math bold"),
        .init(insertion: #"\mathrm{}"#, category: "math", detail: "Math roman"),
        .init(insertion: #"\mathcal{}"#, category: "math", detail: "Math calligraphic"),
        .init(insertion: #"\mathbb{}"#, category: "math", detail: "Blackboard bold"),
        .init(insertion: #"\alpha"#, category: "math", detail: "Greek alpha"),
        .init(insertion: #"\beta"#, category: "math", detail: "Greek beta"),
        .init(insertion: #"\gamma"#, category: "math", detail: "Greek gamma"),
        .init(insertion: #"\delta"#, category: "math", detail: "Greek delta"),
        .init(insertion: #"\epsilon"#, category: "math", detail: "Greek epsilon"),
        .init(insertion: #"\theta"#, category: "math", detail: "Greek theta"),
        .init(insertion: #"\lambda"#, category: "math", detail: "Greek lambda"),
        .init(insertion: #"\mu"#, category: "math", detail: "Greek mu"),
        .init(insertion: #"\pi"#, category: "math", detail: "Greek pi"),
        .init(insertion: #"\sigma"#, category: "math", detail: "Greek sigma"),
        .init(insertion: #"\phi"#, category: "math", detail: "Greek phi"),
        .init(insertion: #"\omega"#, category: "math", detail: "Greek omega"),
        .init(insertion: #"\times"#, category: "math", detail: "Multiplication symbol"),
        .init(insertion: #"\cdot"#, category: "math", detail: "Centered dot"),
        .init(insertion: #"\approx"#, category: "math", detail: "Approximately equal"),
        .init(insertion: #"\neq"#, category: "math", detail: "Not equal"),
        .init(insertion: #"\leq"#, category: "math", detail: "Less-than or equal"),
        .init(insertion: #"\geq"#, category: "math", detail: "Greater-than or equal")
    ]

    static func suggestions(prefix: String, source: String) -> [LaTeXCompletionCandidate] {
        guard prefix.hasPrefix("\\") else { return [] }
        let normalizedPrefix = prefix.lowercased()
        let usedCommands = usedCommandCandidates(in: source)
        let merged = builtInCandidates + usedCommands
        var seen: Set<String> = []
        return merged
            .filter { normalizedPrefix == "\\" || $0.insertion.lowercased().hasPrefix(normalizedPrefix) }
            .filter { $0.insertion.lowercased() != normalizedPrefix }
            .filter { seen.insert($0.insertion).inserted }
            .sorted { lhs, rhs in
                let lhsPriority = completionPriority(for: lhs.insertion, prefix: normalizedPrefix)
                let rhsPriority = completionPriority(for: rhs.insertion, prefix: normalizedPrefix)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                if lhs.category != rhs.category { return lhs.category < rhs.category }
                return lhs.insertion.localizedStandardCompare(rhs.insertion) == .orderedAscending
            }
    }

    private static func completionPriority(for insertion: String, prefix: String) -> Int {
        let commonOrder = [
            #"\section{}"#,
            #"\subsection{}"#,
            #"\subsubsection{}"#,
            #"\textbf{}"#,
            #"\cite{}"#,
            #"\ref{}"#,
            #"\label{}"#,
            #"\includegraphics[]{}"#,
            #"\begin{}"#,
            #"\begin{document}"#,
            #"\begin{figure}"#,
            #"\begin{table}"#,
            #"\begin{equation}"#,
            #"\begin{align}"#,
            #"\begin{itemize}"#,
            #"\begin{enumerate}"#,
            #"\item"#,
            #"\usepackage{}"#,
            #"\documentclass{}"#
        ]
        if let index = commonOrder.firstIndex(of: insertion) { return index }
        if prefix != "\\", insertion.lowercased().hasPrefix(prefix) { return 100 }
        switch insertion {
        case _ where insertion.hasPrefix(#"\begin"#): return 200
        case _ where insertion.hasPrefix(#"\end"#): return 210
        default: return 1_000
        }
    }

    static func argumentSuggestions(
        command: String,
        prefix: String,
        context: LaTeXCompletionContext
    ) -> [LaTeXCompletionCandidate] {
        let values: [(String, String, String)]
        switch command {
        case "cite", "citet", "citep", "citealp", "autocite", "parencite", "textcite":
            values = context.citations.map { ($0, "cite", "Bibliography key") }
        case "ref", "eqref", "autoref", "cref", "Cref", "pageref":
            values = context.labels.map { ($0, "ref", "Document label") }
        case "includegraphics":
            values = context.graphicsFiles.map { ($0, "file", "Project file") }
        case "input", "include":
            values = context.projectFiles.map { ($0, "file", "Project file") }
        case "begin", "end":
            values = commonEnvironmentNames.map { ($0, "env", "LaTeX environment") }
        default:
            return []
        }
        let normalized = prefix.lowercased()
        return values
            .filter { normalized.isEmpty || $0.0.lowercased().hasPrefix(normalized) }
            .map { LaTeXCompletionCandidate(insertion: $0.0, category: $0.1, detail: $0.2) }
    }

    static func shouldTriggerCompletion(afterChangeIn source: NSString, selection: NSRange) -> Bool {
        guard selection.length == 0,
              selection.location <= source.length else { return false }
        if let argument = argumentContext(in: source, cursorLocation: selection.location) {
            return argument.prefix.isEmpty
                && ["cite", "citet", "citep", "citealp", "autocite", "parencite", "textcite", "ref", "eqref", "autoref", "cref", "Cref", "pageref", "includegraphics", "input", "include"].contains(argument.command)
        }
        guard let command = commandPrefix(in: source, cursorLocation: selection.location) else { return false }
        return command.prefix == "\\"
    }

    static func commandPrefix(in source: NSString, cursorLocation: Int) -> (prefix: String, range: NSRange)? {
        guard cursorLocation <= source.length else { return nil }
        var start = cursorLocation
        while start > 0 {
            let previous = source.character(at: start - 1)
            if previous == 92 {
                start -= 1
                break
            }
            guard CharacterSet.alphanumerics.contains(UnicodeScalar(previous)!) || previous == 64 || previous == 42 else {
                return nil
            }
            start -= 1
        }
        guard start < cursorLocation || (start == cursorLocation && start > 0),
              source.character(at: start) == 92 else { return nil }
        let range = NSRange(location: start, length: cursorLocation - start)
        return (source.substring(with: range), range)
    }

    static func argumentContext(in source: NSString, cursorLocation: Int) -> (command: String, prefix: String, range: NSRange)? {
        guard cursorLocation <= source.length else { return nil }
        guard cursorLocation > 0 else { return nil }
        let previous = source.character(at: cursorLocation - 1)
        // Fast preflight: argument completion is only useful while the caret is
        // still inside a short command argument. Avoid running a regular
        // expression over the whole document on every ordinary keystroke.
        let previousIsWord = UnicodeScalar(previous)
            .map { CharacterSet.alphanumerics.contains($0) }
            ?? false
        guard previous == 123
                || previous == 44
                || previous == 45
                || previous == 95
                || previous == 47
                || previous == 46
                || previous == 58
                || previous == 42
                || previous == 64
                || previous == 92
                || previousIsWord else {
            return nil
        }
        let windowLength = min(cursorLocation, 420)
        let windowStart = cursorLocation - windowLength
        let before = source.substring(with: NSRange(location: windowStart, length: windowLength))
        guard let regex = try? NSRegularExpression(
            pattern: #"\\([A-Za-z]+)\*?(?:\[[^\]]*\])?\{([^{}]*)$"#
        ) else { return nil }
        let nsBefore = before as NSString
        guard let match = regex.matches(in: before, range: NSRange(location: 0, length: nsBefore.length)).last,
              match.numberOfRanges >= 3 else { return nil }
        let command = nsBefore.substring(with: match.range(at: 1))
        let prefix = nsBefore.substring(with: match.range(at: 2))
        return (command, prefix, NSRange(location: windowStart + match.range(at: 2).location, length: (prefix as NSString).length))
    }

    private static let commonEnvironmentNames = [
        "document", "figure", "table", "equation", "align", "itemize", "enumerate",
        "abstract", "theorem", "proof", "algorithm", "tabular", "center", "minipage"
    ]

    private static func usedCommandCandidates(in source: String) -> [LaTeXCompletionCandidate] {
        let pattern = #"\\[A-Za-z@]+\*?(?:\{\}){0,2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsSource = source as NSString
        return regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
            .prefix(120)
            .map { match in
                LaTeXCompletionCandidate(
                    insertion: nsSource.substring(with: match.range),
                    category: "used",
                    detail: "Already used in this document"
                )
            }
    }
}

struct SourcePanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var findBarShowsReplace = false
    @State private var findBarVisible = false
    @State private var findQuery = ""
    @State private var replaceQuery = ""
    @State private var activeFindIndex = 0

    private var findMatches: [NSRange] {
        SourceFindController.matches(in: model.sourceText, query: findQuery)
    }

    private var activeFindRange: NSRange? {
        guard findMatches.indices.contains(activeFindIndex) else { return nil }
        return findMatches[activeFindIndex]
    }

    private var completionContext: LaTeXCompletionContext {
        return LaTeXCompletionContext(
            index: model.completionIndex,
            projectFiles: model.projectFiles
                .filter { [.tex, .style, .bibliography].contains($0.kind) }
                .map(\.relativePath)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.selectedFile?.relativePath ?? L10n.text("source.noFile"))
                    .sourceLeafFont(.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if model.hasUnsavedChanges {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                        .help(L10n.text("status.unsaved"))
                }
                Spacer()
                Button {
                    model.saveNow()
                } label: {
                    Label(L10n.text("action.save"), systemImage: "square.and.arrow.down")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!model.canSaveCurrentFile || !model.hasUnsavedChanges)
                .help(L10n.text("action.save"))
                if model.configuration.showSelectionButton {
                    Button {
                        model.attachCurrentSelection()
                    } label: {
                        Label(L10n.text("selection.askAI"), systemImage: "sparkles")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedRange.length == 0)
                    .help(model.selectedRange.length == 0
                        ? L10n.text("selection.selectFirst")
                        : L10n.text("selection.askAI"))
                    .keyboardShortcut("k", modifiers: [.option, .command])
                }
                if model.syncTeXDocument != nil, model.selectedFile?.kind == .tex {
                    Button {
                    model.locateSourceInPDF()
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.text("synctex.showInPDF"))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.bar)

            if model.selectedFile?.kind == .tex {
                LaTeXSourceToolbar()
            }
            if findBarVisible {
                SourceFindBar(
                    query: $findQuery,
                    replacement: $replaceQuery,
                    showsReplace: $findBarShowsReplace,
                    matchCount: findMatches.count,
                    activeIndex: activeFindIndex,
                    onPrevious: { moveFindSelection(delta: -1) },
                    onNext: { moveFindSelection(delta: 1) },
                    onReplaceCurrent: replaceCurrentFindMatch,
                    onReplaceAll: replaceAllFindMatches,
                    onDone: finishFindEditing,
                    onClose: closeFindBar
                )
            }

            SourceTextView(
                text: Binding(get: { model.sourceText }, set: { model.sourceChanged($0) }),
                selection: $model.selectedRange,
                findRanges: findBarVisible ? findMatches : [],
                activeFindRange: findBarVisible ? activeFindRange : nil,
                completionContext: completionContext,
                commandRequest: model.pendingLaTeXEdit,
                showSelectionButton: model.configuration.showSelectionButton,
                editorTheme: model.editorTheme,
                editorFontFamily: model.editorFontFamily,
                editorFontSize: model.editorFontSize,
                onAskAI: model.attachCurrentSelection,
                onCommandApplied: model.acknowledgeLaTeXEdit
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .sourceLeafShowFind)) { _ in
            openFindBarFromSelection()
        }
        .onChange(of: findQuery) { _, _ in normalizeActiveFindIndexAndFocus() }
        .onChange(of: model.sourceText) { _, _ in normalizeActiveFindIndexAndFocus(scroll: false) }
    }

    private func openFindBarFromSelection() {
        if !findBarVisible,
           model.selectedRange.length > 0,
           NSMaxRange(model.selectedRange) <= (model.sourceText as NSString).length {
            findQuery = (model.sourceText as NSString).substring(with: model.selectedRange)
        }
        findBarVisible = true
        normalizeActiveFindIndexAndFocus()
    }

    private func closeFindBar() {
        findBarVisible = false
        findQuery = ""
        activeFindIndex = 0
    }

    private func finishFindEditing() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func normalizeActiveFindIndexAndFocus(scroll: Bool = true) {
        guard !findMatches.isEmpty else {
            activeFindIndex = 0
            return
        }
        if !findMatches.indices.contains(activeFindIndex) { activeFindIndex = 0 }
        if scroll { focusActiveFindMatch() }
    }

    private func focusActiveFindMatch() {
        guard let activeFindRange else { return }
        model.selectedRange = activeFindRange
    }

    private func moveFindSelection(delta: Int) {
        guard !findMatches.isEmpty else { return }
        activeFindIndex = (activeFindIndex + delta + findMatches.count) % findMatches.count
        focusActiveFindMatch()
    }

    private func replaceCurrentFindMatch() {
        guard let activeFindRange,
              NSMaxRange(activeFindRange) <= (model.sourceText as NSString).length else { return }
        let next = NSMutableString(string: model.sourceText)
        next.replaceCharacters(in: activeFindRange, with: replaceQuery)
        model.sourceChanged(next as String)
        model.selectedRange = NSRange(location: activeFindRange.location, length: (replaceQuery as NSString).length)
        normalizeActiveFindIndexAndFocus(scroll: false)
    }

    private func replaceAllFindMatches() {
        guard !findQuery.isEmpty else { return }
        model.sourceChanged(SourceFindController.replacingAllMatches(
            in: model.sourceText,
            query: findQuery,
            replacement: replaceQuery
        ))
        activeFindIndex = 0
    }
}

enum SourceFindController {
    static func matches(in source: String, query: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let nsSource = source as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsSource.length)
        while searchRange.length > 0 {
            let match = nsSource.range(of: query, options: [.caseInsensitive], range: searchRange)
            guard match.location != NSNotFound, match.length > 0 else { break }
            ranges.append(match)
            let nextLocation = match.location + match.length
            searchRange = NSRange(location: nextLocation, length: nsSource.length - nextLocation)
        }
        return ranges
    }

    static func replacingAllMatches(in source: String, query: String, replacement: String) -> String {
        let ranges = matches(in: source, query: query)
        guard !ranges.isEmpty else { return source }
        let next = NSMutableString(string: source)
        for range in ranges.reversed() {
            next.replaceCharacters(in: range, with: replacement)
        }
        return next as String
    }
}

private struct SourceFindBar: View {
    @Binding var query: String
    @Binding var replacement: String
    @Binding var showsReplace: Bool
    let matchCount: Int
    let activeIndex: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onReplaceCurrent: () -> Void
    let onReplaceAll: () -> Void
    let onDone: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.text("source.find"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onDone)
                Text(matchCount == 0 ? "0/0" : "\(activeIndex + 1)/\(matchCount)")
                    .sourceLeafFont(.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 46, alignment: .trailing)
                Button(action: onPrevious) { Image(systemName: "chevron.up") }
                    .disabled(matchCount == 0)
                    .help(L10n.text("source.findPrevious"))
                Button(action: onNext) { Image(systemName: "chevron.down") }
                    .disabled(matchCount == 0)
                    .help(L10n.text("source.findNext"))
                Toggle(isOn: $showsReplace) {
                    Text(L10n.text("source.replace"))
                }
                .toggleStyle(.checkbox)
                Button(L10n.text("action.done"), action: onDone)
                    .help(L10n.text("source.findDoneHelp"))
                Button(action: onClose) { Image(systemName: "xmark") }
                    .help(L10n.text("action.close"))
            }
            .buttonStyle(.borderless)
            if showsReplace {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(.secondary)
                    TextField(L10n.text("source.replaceWith"), text: $replacement)
                        .textFieldStyle(.roundedBorder)
                    Button(L10n.text("source.replaceCurrent"), action: onReplaceCurrent)
                        .disabled(matchCount == 0)
                    Button(L10n.text("source.replaceAll"), action: onReplaceAll)
                        .disabled(matchCount == 0)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct LaTeXSourceToolbar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullToolbar
                .fixedSize(horizontal: true, vertical: false)
            compactToolbar
        }
        .font(.system(size: 11 * model.interfaceFontScale))
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var fullToolbar: some View {
        HStack(spacing: 9) {
            findButton
            Divider().frame(height: 17)
            formatButton(.bold, key: "source.format.bold", symbol: "bold")
            formatButton(.italic, key: "source.format.italic", symbol: "italic")
            formatButton(.underline, key: "source.format.underline", symbol: "underline")
            formatButton(.toggleComment, key: "source.format.toggleComment", symbol: "percent")
            formatButton(.indentLines, key: "source.format.indent", symbol: "increase.indent")
            formatButton(.outdentLines, key: "source.format.outdent", symbol: "decrease.indent")
            Divider().frame(height: 17)
            headingMenu
            fontSizeMenu
            mathMenu
            insertMenu
        }
    }

    private var compactToolbar: some View {
        HStack(spacing: 11) {
            findButton
            formatButton(.bold, key: "source.format.bold", symbol: "bold")
            formatButton(.italic, key: "source.format.italic", symbol: "italic")
            formatButton(.underline, key: "source.format.underline", symbol: "underline")
            formatButton(.toggleComment, key: "source.format.toggleComment", symbol: "percent")
            Menu {
                Section(L10n.text("source.toolbar.editing")) { editingItems }
                Section(L10n.text("source.toolbar.heading")) { headingItems }
                Section(L10n.text("source.toolbar.fontSize")) { fontSizeItems }
                Section(L10n.text("source.toolbar.math")) { mathItems }
                Section(L10n.text("source.toolbar.insert")) { insertItems }
            } label: {
                Label(L10n.text("source.toolbar.more"), systemImage: "ellipsis.circle")
            }
            .accessibilityLabel(L10n.text("source.toolbar.more"))
        }
    }

    private var findButton: some View {
        Button { NotificationCenter.default.post(name: .sourceLeafShowFind, object: nil) } label: {
            Image(systemName: "magnifyingglass")
        }
        .buttonStyle(.borderless)
        .help(L10n.text("source.findReplace"))
        .accessibilityLabel(L10n.text("source.findReplace"))
    }

    private var headingMenu: some View {
        Menu { headingItems } label: {
            Label(L10n.text("source.toolbar.heading"), systemImage: "textformat.size")
        }
    }

    private var fontSizeMenu: some View {
        Menu { fontSizeItems } label: {
            Label(L10n.text("source.toolbar.fontSize"), systemImage: "textformat")
        }
    }

    private var mathMenu: some View {
        Menu { mathItems } label: {
            Label(L10n.text("source.toolbar.math"), systemImage: "function")
        }
    }

    private var insertMenu: some View {
        Menu { insertItems } label: {
            Label(L10n.text("source.toolbar.insert"), systemImage: "plus")
        }
    }

    @ViewBuilder private var editingItems: some View {
        menuButton(.toggleComment, key: "source.format.toggleComment")
        menuButton(.indentLines, key: "source.format.indent")
        menuButton(.outdentLines, key: "source.format.outdent")
    }

    @ViewBuilder private var headingItems: some View {
        menuButton(.section, key: "source.heading.section")
        menuButton(.subsection, key: "source.heading.subsection")
        menuButton(.subsubsection, key: "source.heading.subsubsection")
        menuButton(.paragraph, key: "source.heading.paragraph")
    }

    @ViewBuilder private var fontSizeItems: some View {
        menuButton(.tiny, title: "\\tiny")
        menuButton(.scriptsize, title: "\\scriptsize")
        menuButton(.footnotesize, title: "\\footnotesize")
        menuButton(.small, title: "\\small")
        menuButton(.normalsize, title: "\\normalsize")
        menuButton(.large, title: "\\large")
        menuButton(.largeUpper, title: "\\Large")
        menuButton(.largeAllCaps, title: "\\LARGE")
        menuButton(.huge, title: "\\huge")
        menuButton(.hugeUpper, title: "\\Huge")
    }

    @ViewBuilder private var mathItems: some View {
        menuButton(.inlineMath, key: "source.math.inline")
        menuButton(.displayMath, key: "source.math.display")
        menuButton(.equation, key: "source.math.equation")
        Divider()
        menuButton(.fraction, key: "source.math.fraction")
        menuButton(.superscript, key: "source.math.superscript")
        menuButton(.subscriptText, key: "source.math.subscript")
    }

    private var projectImages: [ProjectFile] {
        model.projectFiles
            .filter { $0.kind == .image }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    @ViewBuilder private var insertItems: some View {
        menuButton(.emphasis, key: "source.format.emphasis")
        menuButton(.itemize, key: "source.insert.itemize")
        menuButton(.enumerate, key: "source.insert.enumerate")
        menuButton(.table, key: "source.insert.table")
        menuButton(.figure, key: "source.insert.figure")
        if !projectImages.isEmpty {
            Menu {
                ForEach(projectImages, id: \.relativePath) { image in
                    Button(image.relativePath) { model.insertFigureForProjectImage(relativePath: image.relativePath) }
                }
            } label: {
                Text(L10n.text("source.insert.projectImage"))
            }
        }
        Divider()
        menuButton(.cite, key: "source.insert.cite")
        menuButton(.reference, key: "source.insert.reference")
        menuButton(.label, key: "source.insert.label")
        menuButton(.url, key: "source.insert.url")
    }

    private func formatButton(_ command: LaTeXEditCommand, key: String, symbol: String) -> some View {
        Button { model.performLaTeXEdit(command) } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .help(L10n.text(key))
        .accessibilityLabel(L10n.text(key))
    }

    private func menuButton(_ command: LaTeXEditCommand, key: String) -> some View {
        Button(L10n.text(key)) { model.performLaTeXEdit(command) }
    }

    private func menuButton(_ command: LaTeXEditCommand, title: String) -> some View {
        Button(title) { model.performLaTeXEdit(command) }
    }
}

struct SourceTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var findRanges: [NSRange] = []
    var activeFindRange: NSRange?
    var completionContext = LaTeXCompletionContext()
    var commandRequest: LaTeXEditRequest? = nil
    var showSelectionButton: Bool
    var editorTheme: EditorTheme = .system
    var editorFontFamily: String = EditorFontCatalog.systemMonospaced
    var editorFontSize: Double = 13
    var onAskAI: () -> Void
    var onCommandApplied: (UUID) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else {
            assertionFailure("NSTextView.scrollableTextView() did not provide a text view")
            return NSView()
        }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        let palette = SourceEditorPalette(theme: editorTheme, appearance: textView.effectiveAppearance)
        let container = SourceEditorContainerView(
            scrollView: scrollView,
            textView: textView,
            backgroundColor: palette.background
        )
        scrollView.drawsBackground = true
        scrollView.backgroundColor = palette.background
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = palette.background
        let editorFont = EditorFontCatalog.font(family: editorFontFamily, size: editorFontSize)
        textView.font = editorFont
        textView.textColor = palette.text
        textView.backgroundColor = palette.background
        textView.drawsBackground = true
        textView.insertionPointColor = palette.caret
        textView.selectedTextAttributes = [
            .backgroundColor: palette.selectionBackground,
            .foregroundColor: palette.selectionText
        ]
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: max(scrollView.contentSize.width, 1), height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text
        if NSMaxRange(selection) <= (text as NSString).length {
            textView.setSelectedRange(selection)
        }

        let ruler = LineNumberRulerView(textView: textView)
        ruler.backgroundColor = palette.gutterBackground
        ruler.numberColor = palette.gutterText
        ruler.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalRuler = false
        scrollView.rulersVisible = false

        let glyphOverlay = SourceGlyphOverlayView(textView: textView, palette: palette)
        let completionOverlay = LaTeXCompletionOverlayView()
        completionOverlay.isHidden = true
        container.glyphOverlay = glyphOverlay
        container.completionOverlay = completionOverlay

        container.addSubview(ruler)
        container.addSubview(scrollView)
        container.addSubview(glyphOverlay, positioned: .above, relativeTo: scrollView)
        container.addSubview(completionOverlay, positioned: .above, relativeTo: glyphOverlay)
        NSLayoutConstraint.activate([
            ruler.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            ruler.topAnchor.constraint(equalTo: container.topAnchor),
            ruler.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ruler.widthAnchor.constraint(equalToConstant: 44),
            scrollView.leadingAnchor.constraint(equalTo: ruler.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.glyphOverlay = glyphOverlay
        context.coordinator.completionOverlay = completionOverlay
        completionOverlay.onPick = { [weak coordinator = context.coordinator] index in
            coordinator?.acceptCompletionFromOverlay(at: index)
        }
        context.coordinator.observeScrollView(scrollView)
        glyphOverlay.synchronizeFrame()
        context.coordinator.layoutEditor()
        context.coordinator.applyHighlighting()
        context.coordinator.scheduleInitialHighlighting()
        context.coordinator.applyPendingCommand(commandRequest)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.updateFindHighlights(findRanges, activeRange: activeFindRange)
        if textView.hasMarkedText() {
            context.coordinator.hideCompletionOverlay()
            context.coordinator.applyPendingCommand(commandRequest)
            return
        }
        var requiresFullRefresh = false
        let staleLocalSelectionEcho =
            context.coordinator.lastLocallyEmittedText == textView.string
            && textView.string == text
            && context.coordinator.lastLocallyEmittedSelection == textView.selectedRange()
        if textView.string == text {
            context.coordinator.lastLocallyEmittedText = nil
        } else if SourceTextSynchronization.shouldApplyExternalText(
            incoming: text,
            nativeText: textView.string,
            lastLocallyEmittedText: context.coordinator.lastLocallyEmittedText
        ) {
            let visible = textView.enclosingScrollView?.contentView.bounds
            let selectedRange = textView.selectedRange()
            textView.string = text
            context.coordinator.lastLocallyEmittedText = nil
            context.coordinator.applyHighlighting()
            if let visible { textView.enclosingScrollView?.contentView.scroll(to: visible.origin) }
            let length = (text as NSString).length
            let restored = NSRange(location: min(selectedRange.location, length), length: 0)
            textView.setSelectedRange(restored)
            requiresFullRefresh = true
        }
        if textView.selectedRange() == selection {
            context.coordinator.lastLocallyEmittedSelection = nil
        } else if staleLocalSelectionEcho {
            context.coordinator.lastLocallyEmittedSelection = nil
        } else if context.coordinator.shouldIgnoreProtectedSelectionEcho(selection) {
            context.coordinator.lastLocallyEmittedSelection = nil
            context.coordinator.commitNativeSelectionToBinding()
        } else if context.coordinator.shouldIgnoreSelectionEchoDuringLocalEdit(
            selection,
            nativeSelection: textView.selectedRange(),
            boundText: text,
            nativeText: textView.string
        ) {
            context.coordinator.lastLocallyEmittedSelection = nil
            context.coordinator.commitNativeSelectionToBinding()
        } else if NSMaxRange(selection) <= (textView.string as NSString).length {
            textView.setSelectedRange(selection)
            textView.scrollRangeToVisible(selection)
            context.coordinator.lastLocallyEmittedSelection = nil
        }
        context.coordinator.applyPendingCommand(commandRequest)
        if context.coordinator.appliedStyleSignature != nil,
           context.coordinator.appliedStyleSignature != context.coordinator.currentStyleSignature {
            context.coordinator.applyHighlighting()
            requiresFullRefresh = true
        }
        // A drag selection publishes dozens of binding updates per second. The
        // NSTextView has already updated its selection and layout at this point;
        // forcing TextKit to lay out the whole document again makes the painted
        // selection trail behind the pointer on large files.
        if requiresFullRefresh {
            context.coordinator.layoutEditor()
            context.coordinator.invalidateVisibleEditor()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceTextView
        var textView: NSTextView?
        weak var ruler: LineNumberRulerView?
        weak var glyphOverlay: SourceGlyphOverlayView?
        weak var completionOverlay: LaTeXCompletionOverlayView?
        private var activeCompletionState: LaTeXCompletionState?
        private var applyingCompletionEdit = false
        private var highlighting = false
        private(set) var appliedStyleSignature: String?
        private var lastAppliedCommandID: UUID?
        private var resettingHorizontalScroll = false
        private var completedWindowHighlight = false
        private var selectionSyncTimer: Timer?
        private var highlightTimer: Timer?
        private var lastLocalEditDate = Date.distantPast
        private var protectedSelectionEcho: NSRange?
        private var applyingSmartPairEdit = false
        private var applyingLineShiftEdit = false
        var lastLocallyEmittedText: String?
        var lastLocallyEmittedSelection: NSRange?

        var currentStyleSignature: String {
            let appearance = textView?.effectiveAppearance.name.rawValue ?? "none"
            return "\(parent.editorTheme.rawValue)|\(parent.editorFontFamily)|\(parent.editorFontSize)|\(appearance)"
        }

        init(parent: SourceTextView) { self.parent = parent }

        func tearDown() {
            selectionSyncTimer?.invalidate()
            selectionSyncTimer = nil
            highlightTimer?.invalidate()
            highlightTimer = nil
            NotificationCenter.default.removeObserver(self)
            textView?.delegate = nil
            completionOverlay?.removeFromSuperview()
            completionOverlay = nil
            glyphOverlay?.removeFromSuperview()
            glyphOverlay = nil
            activeCompletionState = nil
            ruler = nil
            textView = nil
        }

        func observeScrollView(_ scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        @objc private func scrollBoundsDidChange(_ notification: Notification) {
            if !resettingHorizontalScroll,
               let clipView = notification.object as? NSClipView,
               abs(clipView.bounds.origin.x) > 0.5 {
                resettingHorizontalScroll = true
                clipView.scroll(to: NSPoint(x: 0, y: clipView.bounds.origin.y))
                clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
                resettingHorizontalScroll = false
            }
            ruler?.scrollPositionDidChange()
            glyphOverlay?.synchronizeFrame()
            glyphOverlay?.needsDisplay = true
            if completionOverlay?.isShowing == true { updateCompletionOverlayIfNeeded() }
        }

        func textDidChange(_ notification: Notification) {
            guard !highlighting, let textView else { return }
            normalizeCompletionPlaceholderSelectionIfNeeded()
            let nativeSelection = textView.selectedRange()
            lastLocalEditDate = Date()
            lastLocallyEmittedSelection = nativeSelection
            if parent.selection != nativeSelection {
                protectedSelectionEcho = parent.selection
            }
            guard !textView.hasMarkedText() else {
                ruler?.needsDisplay = true
                glyphOverlay?.restartCaretBlink()
                glyphOverlay?.needsDisplay = true
                return
            }
            lastLocallyEmittedText = textView.string
            parent.text = textView.string
            scheduleDeferredHighlighting()
            commitSelectionToBinding()
            scheduleSelectionCommit(after: 0.016)
            updateCompletionOverlayIfNeeded()
            ruler?.needsDisplay = true
            glyphOverlay?.restartCaretBlink()
            glyphOverlay?.needsDisplay = true
        }

        private func scheduleDeferredHighlighting(after delay: TimeInterval = 0.45) {
            highlightTimer?.invalidate()
            let timer = Timer(
                timeInterval: delay,
                target: self,
                selector: #selector(applyDeferredHighlighting),
                userInfo: nil,
                repeats: false
            )
            highlightTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        private func normalizeCompletionPlaceholderSelectionIfNeeded() {
            guard let textView else { return }
            let selection = textView.selectedRange()
            guard let normalized = normalizedCompletionPlaceholderSelection(selection, in: textView) else { return }
            textView.setSelectedRange(normalized)
        }

        private func normalizedCompletionPlaceholderSelection(_ selection: NSRange, in textView: NSTextView) -> NSRange? {
            guard selection.length == 2,
                  NSMaxRange(selection) <= (textView.string as NSString).length else { return nil }
            let source = textView.string as NSString
            let selected = source.substring(with: selection)
            guard selected == "{}" || selected == "[]" else { return nil }
            guard selection.location > 0 else { return nil }
            let previous = source.character(at: selection.location - 1)
            guard let scalar = UnicodeScalar(previous),
                  CharacterSet.alphanumerics.contains(scalar) || previous == 92 else { return nil }
            return NSRange(location: selection.location + 1, length: 0)
        }

        @objc private func applyDeferredHighlighting() {
            applyHighlighting()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            normalizeCompletionPlaceholderSelectionIfNeeded()
            lastLocallyEmittedSelection = textView.selectedRange()
            guard !textView.hasMarkedText() else {
                hideCompletionOverlay()
                glyphOverlay?.selectionDidChange()
                return
            }
            updateCompletionOverlayIfNeeded()
            // Keep AppKit's native interaction immediate, but coalesce the
            // higher-level SwiftUI binding while a pointer drag is in flight.
            scheduleSelectionCommit()
            glyphOverlay?.selectionDidChange()
        }

        func textView(
            _ textView: NSTextView,
            willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
            toCharacterRange newSelectedCharRange: NSRange
        ) -> NSRange {
            normalizedCompletionPlaceholderSelection(newSelectedCharRange, in: textView) ?? newSelectedCharRange
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if handleCompletionCommand(commandSelector, in: textView) { return true }
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                return applySmartNewlineCommand(in: textView)
            case #selector(NSResponder.insertBacktab(_:)):
                return applyLineShiftCommand(.outdentLines, in: textView)
            case #selector(NSResponder.insertTab(_:)):
                if textView.selectedRange().length > 0 {
                    return applyLineShiftCommand(.indentLines, in: textView)
                }
                if jumpToNextLaTeXPlaceholderIfNeeded(in: textView) { return true }
                return applyLineShiftCommand(.indentLines, in: textView)
            default:
                return false
            }
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !applyingSmartPairEdit,
                  !applyingLineShiftEdit,
                  !highlighting,
                  !textView.hasMarkedText(),
                  let replacementString,
                  affectedCharRange.location != NSNotFound else { return true }
            if skipDuplicateCloserIfNeeded(
                replacementString,
                in: textView,
                affectedRange: affectedCharRange
            ) {
                return false
            }
            if insertSmartPairIfNeeded(
                replacementString,
                in: textView,
                affectedRange: affectedCharRange
            ) {
                return false
            }
            return true
        }

        private func applySmartNewlineCommand(in textView: NSTextView) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            let edit = LaTeXSourceFormatter.newlineEdit(
                source: textView.string,
                selection: textView.selectedRange()
            )
            guard edit.replacementRange.location != NSNotFound,
                  NSMaxRange(edit.replacementRange) <= (textView.string as NSString).length else { return false }
            let originalSelection = textView.selectedRange()
            let undoManager = textView.undoManager
            undoManager?.beginUndoGrouping()
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.restoreSelection(originalSelection, opposite: edit.resultingSelection)
                }
            }
            applyingLineShiftEdit = true
            defer { applyingLineShiftEdit = false }
            textView.insertText(edit.replacement, replacementRange: edit.replacementRange)
            textView.setSelectedRange(edit.resultingSelection)
            textView.scrollRangeToVisible(edit.resultingSelection)
            undoManager?.endUndoGrouping()
            parent.selection = edit.resultingSelection
            glyphOverlay?.selectionDidChange()
            return true
        }

        private func insertSmartPairIfNeeded(
            _ replacement: String,
            in textView: NSTextView,
            affectedRange: NSRange
        ) -> Bool {
            guard let closing = Self.smartPairClosingDelimiter(for: replacement),
                  NSMaxRange(affectedRange) <= (textView.string as NSString).length else { return false }
            let source = textView.string as NSString
            let selected = affectedRange.length > 0 ? source.substring(with: affectedRange) : ""
            let pair = replacement + selected + closing
            let caret = NSRange(location: affectedRange.location + (replacement as NSString).length + (selected as NSString).length, length: 0)
            applySmartPairEdit(pair, replacementRange: affectedRange, resultingSelection: caret, in: textView)
            return true
        }

        private func skipDuplicateCloserIfNeeded(
            _ replacement: String,
            in textView: NSTextView,
            affectedRange: NSRange
        ) -> Bool {
            guard affectedRange.length == 0,
                  Self.smartPairOpeningDelimiter(for: replacement) != nil,
                  affectedRange.location < (textView.string as NSString).length else { return false }
            let source = textView.string as NSString
            let next = source.substring(with: NSRange(location: affectedRange.location, length: 1))
            guard next == replacement else { return false }
            textView.setSelectedRange(NSRange(location: affectedRange.location + (replacement as NSString).length, length: 0))
            commitSelectionToBinding()
            glyphOverlay?.selectionDidChange()
            return true
        }

        private func applySmartPairEdit(
            _ replacement: String,
            replacementRange: NSRange,
            resultingSelection: NSRange,
            in textView: NSTextView
        ) {
            applyingSmartPairEdit = true
            if textView.shouldChangeText(in: replacementRange, replacementString: replacement) {
                textView.textStorage?.replaceCharacters(in: replacementRange, with: replacement)
                textView.didChangeText()
                textView.setSelectedRange(resultingSelection)
                textView.scrollRangeToVisible(resultingSelection)
            }
            applyingSmartPairEdit = false
        }

        private func applyLineShiftCommand(_ command: LaTeXEditCommand, in textView: NSTextView) -> Bool {
            guard command == .indentLines || command == .outdentLines else { return false }
            guard !textView.hasMarkedText() else { return false }
            let edit = LaTeXSourceFormatter.edit(
                command: command,
                source: textView.string,
                selection: textView.selectedRange()
            )
            guard edit.replacementRange.location != NSNotFound,
                  NSMaxRange(edit.replacementRange) <= (textView.string as NSString).length else { return false }
            let originalSelection = textView.selectedRange()
            let undoManager = textView.undoManager
            undoManager?.beginUndoGrouping()
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.restoreSelection(originalSelection, opposite: edit.resultingSelection)
                }
            }
            applyingLineShiftEdit = true
            textView.insertText(edit.replacement, replacementRange: edit.replacementRange)
            applyingLineShiftEdit = false
            textView.setSelectedRange(edit.resultingSelection)
            textView.scrollRangeToVisible(edit.resultingSelection)
            undoManager?.endUndoGrouping()
            parent.selection = edit.resultingSelection
            glyphOverlay?.selectionDidChange()
            return true
        }

        private static func smartPairClosingDelimiter(for opening: String) -> String? {
            switch opening {
            case "{": "}"
            case "[": "]"
            case "(": ")"
            case "$": "$"
            default: nil
            }
        }

        private static func smartPairOpeningDelimiter(for closing: String) -> String? {
            switch closing {
            case "}": "{"
            case "]": "["
            case ")": "("
            case "$": "$"
            default: nil
            }
        }

        private func jumpToNextLaTeXPlaceholderIfNeeded(in textView: NSTextView) -> Bool {
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }
            let source = textView.string as NSString
            guard selection.location <= source.length,
                  let currentClose = Self.currentPlaceholderClosingLocation(in: source, cursorLocation: selection.location),
                  let nextPlaceholder = Self.nextEmptyPlaceholder(in: source, searchFrom: currentClose + 1) else {
                return false
            }
            textView.setSelectedRange(NSRange(location: nextPlaceholder.location + 1, length: 0))
            textView.scrollRangeToVisible(NSRange(location: nextPlaceholder.location + 1, length: 0))
            commitSelectionToBinding()
            glyphOverlay?.selectionDidChange()
            return true
        }

        private static func currentPlaceholderClosingLocation(in source: NSString, cursorLocation: Int) -> Int? {
            guard cursorLocation <= source.length else { return nil }
            var openLocation: Int?
            var openingDelimiter: unichar?
            var index = cursorLocation - 1
            while index >= 0 {
                let character = source.character(at: index)
                if character == 125 || character == 93 { return nil }
                if character == 123 || character == 91 {
                    openLocation = index
                    openingDelimiter = character
                    break
                }
                index -= 1
            }
            guard let openLocation, let openingDelimiter else { return nil }
            let closingDelimiter: unichar = openingDelimiter == 123 ? 125 : 93
            var close = max(cursorLocation, openLocation + 1)
            while close < source.length {
                let character = source.character(at: close)
                if character == openingDelimiter { return nil }
                if character == closingDelimiter { return close }
                close += 1
            }
            return nil
        }

        private static func nextEmptyPlaceholder(in source: NSString, searchFrom: Int) -> NSRange? {
            guard searchFrom < source.length else { return nil }
            var index = searchFrom
            while index + 1 < source.length {
                let current = source.character(at: index)
                let next = source.character(at: index + 1)
                if (current == 123 && next == 125) || (current == 91 && next == 93) {
                    return NSRange(location: index, length: 2)
                }
                index += 1
            }
            return nil
        }

        private func scheduleSelectionCommit(after delay: TimeInterval = 0.05) {
            selectionSyncTimer?.invalidate()
            let timer = Timer(timeInterval: delay, target: self, selector: #selector(commitSelectionToBinding), userInfo: nil, repeats: false)
            selectionSyncTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        @objc private func commitSelectionToBinding() {
            guard let textView else { return }
            let range = textView.selectedRange()
            lastLocallyEmittedSelection = range
            if parent.selection != range { parent.selection = range }
            protectedSelectionEcho = nil
        }

        func commitNativeSelectionToBinding() {
            selectionSyncTimer?.invalidate()
            selectionSyncTimer = nil
            commitSelectionToBinding()
        }

        func shouldIgnoreProtectedSelectionEcho(_ range: NSRange) -> Bool {
            guard protectedSelectionEcho == range else { return false }
            return Date().timeIntervalSince(lastLocalEditDate) < 0.35
        }

        func shouldIgnoreSelectionEchoDuringLocalEdit(
            _ range: NSRange,
            nativeSelection: NSRange,
            boundText: String,
            nativeText: String
        ) -> Bool {
            guard Date().timeIntervalSince(lastLocalEditDate) < 0.28,
                  boundText == nativeText,
                  range.length == 0,
                  nativeSelection.length == 0 else { return false }
            // During rapid typing the NSTextView is the source of truth. A
            // zero-length binding selection behind the native insertion point
            // is almost always a stale SwiftUI echo from the previous key
            // event; accepting it reorders text (`test` -> `tset`). Explicit
            // jumps such as find/outline happen outside this tiny post-edit
            // window and are still applied normally.
            return range.location < nativeSelection.location
        }

        func hideCompletionOverlay() {
            activeCompletionState = nil
            completionOverlay?.hide()
        }

        private func updateCompletionOverlayIfNeeded() {
            guard !applyingCompletionEdit,
                  let textView,
                  textView.window?.firstResponder === textView,
                  !textView.hasMarkedText(),
                  textView.selectedRange().length == 0 else {
                hideCompletionOverlay()
                return
            }
            guard let state = completionState(in: textView), !state.candidates.isEmpty else {
                hideCompletionOverlay()
                return
            }
            activeCompletionState = state
            guard let anchor = completionAnchorRect(for: textView.selectedRange().location, in: textView) else {
                completionOverlay?.show(candidates: state.candidates, selectedIndex: state.selectedIndex, anchor: .zero, palette: currentPalette())
                return
            }
            completionOverlay?.show(candidates: state.candidates, selectedIndex: state.selectedIndex, anchor: anchor, palette: currentPalette())
        }

        private func completionState(in textView: NSTextView) -> LaTeXCompletionState? {
            let source = textView.string as NSString
            let cursor = textView.selectedRange().location
            if let argument = LaTeXCompletionEngine.argumentContext(in: source, cursorLocation: cursor) {
                let candidates = LaTeXCompletionEngine.argumentSuggestions(
                    command: argument.command,
                    prefix: argument.prefix,
                    context: parent.completionContext
                )
                return LaTeXCompletionState(replacementRange: argument.range, candidates: candidates, argumentCommand: argument.command)
            }
            guard let command = LaTeXCompletionEngine.commandPrefix(in: source, cursorLocation: cursor),
                  command.prefix.hasPrefix("\\") else { return nil }
            let candidates = LaTeXCompletionEngine.suggestions(prefix: command.prefix, source: textView.string)
            return LaTeXCompletionState(replacementRange: command.range, candidates: candidates)
        }

        private func handleCompletionCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool {
            guard let state = activeCompletionState, completionOverlay?.isShowing == true else { return false }
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                completionOverlay?.moveSelection(delta: 1)
                activeCompletionState?.selectedIndex = completionOverlay?.selectedIndex ?? state.selectedIndex
                return true
            case #selector(NSResponder.moveUp(_:)):
                completionOverlay?.moveSelection(delta: -1)
                activeCompletionState?.selectedIndex = completionOverlay?.selectedIndex ?? state.selectedIndex
                return true
            case #selector(NSResponder.insertTab(_:)),
                 #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                acceptCompletion(in: textView)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                hideCompletionOverlay()
                return true
            default:
                return false
            }
        }

        func acceptCompletionFromOverlay(at index: Int) {
            guard var state = activeCompletionState, let textView else { return }
            state.selectedIndex = min(max(0, index), max(0, state.candidates.count - 1))
            activeCompletionState = state
            acceptCompletion(in: textView, selectedIndexOverride: state.selectedIndex)
        }

        private func acceptCompletion(in textView: NSTextView, selectedIndexOverride: Int? = nil) {
            guard var state = activeCompletionState, !state.candidates.isEmpty else { return }
            state.selectedIndex = min(max(0, selectedIndexOverride ?? completionOverlay?.selectedIndex ?? state.selectedIndex), state.candidates.count - 1)
            let candidate = state.candidates[state.selectedIndex]
            guard NSMaxRange(state.replacementRange) <= (textView.string as NSString).length else { return }
            let insertion = candidate.insertion
            let originalSelection = textView.selectedRange()
            let undoManager = textView.undoManager
            var caret = NSRange(location: state.replacementRange.location + Self.caretOffset(afterInserting: insertion), length: 0)
            textView.breakUndoCoalescing()
            undoManager?.beginUndoGrouping()
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.restoreSelection(originalSelection, opposite: caret)
                }
            }
            applyingCompletionEdit = true
            defer {
                applyingCompletionEdit = false
                undoManager?.endUndoGrouping()
            }
            textView.insertText(insertion, replacementRange: state.replacementRange)
            if state.argumentCommand == "begin" {
                caret = insertMatchingEndEnvironmentIfNeeded(
                    environmentName: insertion,
                    closingBraceLocation: state.replacementRange.location + (insertion as NSString).length,
                    in: textView
                ) ?? caret
            } else if let environmentName = Self.beginEnvironmentName(in: insertion) {
                caret = insertMatchingEndEnvironmentIfNeeded(
                    environmentName: environmentName,
                    closingBraceLocation: state.replacementRange.location + (insertion as NSString).length - 1,
                    in: textView
                ) ?? caret
            }
            textView.setSelectedRange(caret)
            textView.scrollRangeToVisible(caret)
            hideCompletionOverlay()
            commitSelectionToBinding()
        }

        private static func caretOffset(afterInserting insertion: String) -> Int {
            let ns = insertion as NSString
            let placeholderRanges = ["{}", "[]"]
                .map { ns.range(of: $0) }
                .filter { $0.location != NSNotFound }
            if let first = placeholderRanges.min(by: { $0.location < $1.location }) {
                return first.location + 1
            }
            return ns.length
        }

        private static func beginEnvironmentName(in insertion: String) -> String? {
            guard insertion.hasPrefix(#"\begin{"#), insertion.hasSuffix("}") else { return nil }
            let nsInsertion = insertion as NSString
            let start = (#"\begin{"# as NSString).length
            let length = nsInsertion.length - start - 1
            guard length > 0 else { return nil }
            let name = nsInsertion.substring(with: NSRange(location: start, length: length))
            guard name.range(of: #"^[A-Za-z*]+$"#, options: .regularExpression) != nil else { return nil }
            return name
        }

        private func insertMatchingEndEnvironmentIfNeeded(
            environmentName: String,
            closingBraceLocation: Int,
            in textView: NSTextView
        ) -> NSRange? {
            let source = textView.string as NSString
            guard !environmentName.isEmpty,
                  closingBraceLocation >= 0,
                  closingBraceLocation < source.length,
                  source.substring(with: NSRange(location: closingBraceLocation, length: 1)) == "}" else { return nil }
            let closing = "\n\n\\end{\(environmentName)}"
            let insertLocation = closingBraceLocation + 1
            textView.insertText(closing, replacementRange: NSRange(location: insertLocation, length: 0))
            return NSRange(location: insertLocation + 1, length: 0)
        }

        private func completionAnchorRect(for characterIndex: Int, in textView: NSTextView) -> NSRect? {
            guard let scrollView = textView.enclosingScrollView,
                  let container = completionOverlay?.superview,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return nil }
            layoutManager.ensureLayout(for: textContainer)
            let visible = scrollView.contentView.bounds
            let origin = NSPoint(
                x: textView.textContainerOrigin.x - visible.minX,
                y: textView.textContainerOrigin.y - visible.minY
            )
            let rect: NSRect
            let length = (textView.string as NSString).length
            if characterIndex < length {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
                rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
            } else {
                rect = layoutManager.extraLineFragmentRect
            }
            let inClip = rect.offsetBy(dx: origin.x, dy: origin.y)
            guard let superview = textView.enclosingScrollView?.superview else { return nil }
            return superview.convert(inClip, to: container)
        }

        private func currentPalette() -> SourceEditorPalette {
            guard let textView else {
                return SourceEditorPalette(theme: parent.editorTheme, appearance: NSApp.effectiveAppearance)
            }
            return SourceEditorPalette(theme: parent.editorTheme, appearance: textView.effectiveAppearance)
        }

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            if let argument = LaTeXCompletionEngine.argumentContext(
                in: textView.string as NSString,
                cursorLocation: textView.selectedRange().location
            ) {
                index?.pointee = -1
                return LaTeXCompletionEngine.argumentSuggestions(
                    command: argument.command,
                    prefix: argument.prefix,
                    context: parent.completionContext
                ).map(\.insertion)
            }
            guard let command = LaTeXCompletionEngine.commandPrefix(
                in: textView.string as NSString,
                cursorLocation: textView.selectedRange().location
            ) else { return [] }
            index?.pointee = -1
            let candidates = LaTeXCompletionEngine.suggestions(prefix: command.prefix, source: textView.string)
            let slashIsAlreadyInDocument = charRange.location > 0
                && (textView.string as NSString).character(at: charRange.location - 1) == 92
            return candidates.map { candidate in
                slashIsAlreadyInDocument && candidate.insertion.hasPrefix("\\")
                    ? String(candidate.insertion.dropFirst())
                    : candidate.insertion
            }
        }

        @objc func askAI() {
            selectionSyncTimer?.invalidate()
            commitSelectionToBinding()
            parent.onAskAI()
        }

        func applyPendingCommand(_ request: LaTeXEditRequest?) {
            guard let request, request.id != lastAppliedCommandID else { return }
            lastAppliedCommandID = request.id
            executePendingCommand(request, attempt: 0)
        }

        private func executePendingCommand(_ request: LaTeXEditRequest, attempt: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.05)) { [self] in
                guard let textView = textView else { return }
                guard textView.window != nil else {
                    if attempt < 20 { self.executePendingCommand(request, attempt: attempt + 1) }
                    return
                }
                let edit = LaTeXSourceFormatter.edit(
                    command: request.command,
                    source: textView.string,
                    selection: textView.selectedRange(),
                    argument: request.argument
                )
                let originalSelection = textView.selectedRange()
                let undoManager = textView.undoManager
                undoManager?.beginUndoGrouping()
                undoManager?.registerUndo(withTarget: self) { target in
                    MainActor.assumeIsolated {
                        target.restoreSelection(originalSelection, opposite: edit.resultingSelection)
                    }
                }
                textView.insertText(edit.replacement, replacementRange: edit.replacementRange)
                textView.setSelectedRange(edit.resultingSelection)
                undoManager?.endUndoGrouping()
                textView.scrollRangeToVisible(edit.resultingSelection)
                self.parent.selection = edit.resultingSelection
                self.glyphOverlay?.needsDisplay = true
                self.parent.onCommandApplied(request.id)
            }
        }

        private func restoreSelection(_ requested: NSRange, opposite: NSRange) {
            guard let textView else { return }
            let range = clampedSelection(requested, in: textView)
            textView.setSelectedRange(range)
            parent.selection = range
            textView.scrollRangeToVisible(range)
            textView.undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.restoreSelection(opposite, opposite: requested)
                }
            }
            scheduleSelectionRestore(requested)
            glyphOverlay?.selectionDidChange()
        }

        private func scheduleSelectionRestore(_ requested: NSRange) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let textView = self.textView else { return }
                let range = self.clampedSelection(requested, in: textView)
                guard textView.selectedRange() != range else { return }
                textView.setSelectedRange(range)
                self.parent.selection = range
                textView.scrollRangeToVisible(range)
                self.glyphOverlay?.selectionDidChange()
            }
        }

        private func clampedSelection(_ requested: NSRange, in textView: NSTextView) -> NSRange {
            let length = (textView.string as NSString).length
            let location = min(max(0, requested.location), length)
            return NSRange(
                location: location,
                length: min(max(0, requested.length), max(0, length - location))
            )
        }

        func scheduleInitialHighlighting(attempt: Int = 0) {
            guard !completedWindowHighlight else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, !self.completedWindowHighlight else { return }
                guard let textView = self.textView, let window = textView.window else {
                    if attempt < 40 { self.scheduleInitialHighlighting(attempt: attempt + 1) }
                    return
                }
                // SwiftUI performs one more representable/layout transaction
                // after the view first acquires a window. Commit TextStorage
                // attributes after that transaction so the window compositor
                // keeps the glyph layer.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak window] in
                    guard let self, let window, window === self.textView?.window else { return }
                    self.applyHighlighting()
                    self.completedWindowHighlight = true
                    self.invalidateVisibleEditor()
                    var ancestor = self.textView?.superview
                    while let view = ancestor {
                        view.needsDisplay = true
                        ancestor = view.superview
                    }
                    window.contentView?.displayIfNeeded()
                    window.displayIfNeeded()
                }
            }
        }

        func applyHighlighting() {
            guard let textView, let storage = textView.textStorage else { return }
            guard !textView.hasMarkedText() else { return }
            highlighting = true
            let appearance = textView.effectiveAppearance
            let palette = SourceEditorPalette(theme: parent.editorTheme, appearance: appearance)
            let editorFont = EditorFontCatalog.font(
                family: parent.editorFontFamily,
                size: parent.editorFontSize
            )
            let selectedRange = textView.selectedRange()
            let source = textView.string as NSString
            let targetRange = highlightingRange(for: source, in: textView)
            textView.textColor = palette.text
            textView.backgroundColor = palette.background
            textView.font = editorFont
            if let scrollView = textView.enclosingScrollView {
                scrollView.drawsBackground = true
                scrollView.backgroundColor = palette.background
                scrollView.contentView.drawsBackground = true
                scrollView.contentView.backgroundColor = palette.background
                (scrollView.superview as? SourceEditorContainerView)?.backgroundColor = palette.background
            }
            ruler?.backgroundColor = palette.gutterBackground
            ruler?.numberColor = palette.gutterText
            storage.beginEditing()
            storage.setAttributes([
                .font: editorFont,
                .foregroundColor: palette.text
            ], range: targetRange)
            apply(#"\[[^\]\n]*\]"#, color: palette.optionalArgument, storage: storage, source: textView.string, range: targetRange)
            apply(#"\\[A-Za-z@]+\*?"#, color: palette.command, storage: storage, source: textView.string, range: targetRange)
            apply(#"\$[^$\n]*\$"#, color: palette.math, storage: storage, source: textView.string, range: targetRange)
            apply(#"[{}]"#, color: palette.brace, storage: storage, source: textView.string, range: targetRange)
            apply(#"(?<!\\)%.*$"#, color: palette.comment, storage: storage, source: textView.string, range: targetRange, options: [.anchorsMatchLines])
            storage.endEditing()
            if NSMaxRange(selectedRange) <= source.length { textView.setSelectedRange(selectedRange) }
            textView.typingAttributes = [
                .font: editorFont,
                .foregroundColor: palette.text
            ]
            textView.insertionPointColor = palette.caret
            textView.selectedTextAttributes = [
                .backgroundColor: palette.selectionBackground,
                .foregroundColor: palette.selectionText
            ]
            appliedStyleSignature = currentStyleSignature
            glyphOverlay?.palette = palette
            if completionOverlay?.isShowing == true { completionOverlay?.palette = palette }
            textView.layoutManager?.invalidateDisplay(forCharacterRange: targetRange)
            textView.needsDisplay = true
            glyphOverlay?.synchronizeFrame()
            glyphOverlay?.needsDisplay = true
            highlighting = false
        }

        func updateFindHighlights(_ ranges: [NSRange], activeRange: NSRange?) {
            glyphOverlay?.findRanges = ranges
            glyphOverlay?.activeFindRange = activeRange
            glyphOverlay?.needsDisplay = true
        }

        func invalidateVisibleEditor() {
            guard let textView else { return }
            textView.isHidden = false
            textView.alphaValue = 1
            textView.setNeedsDisplay(textView.visibleRect)
            textView.enclosingScrollView?.contentView.needsDisplay = true
            ruler?.needsDisplay = true
            glyphOverlay?.synchronizeFrame()
            glyphOverlay?.needsDisplay = true
        }

        func layoutEditor() {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let width = max(scrollView.contentSize.width, 1)
            guard width.isFinite else { return }
            if abs(textView.frame.width - width) > 0.5 {
                textView.setFrameSize(NSSize(width: width, height: max(textView.frame.height, 1)))
            }
            textView.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            if let textContainer = textView.textContainer {
                textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
                textContainer.widthTracksTextView = true
                textView.layoutManager?.ensureLayout(for: textContainer)
            }
            textView.setNeedsDisplay(textView.visibleRect)
            glyphOverlay?.synchronizeFrame()
        }

        private func apply(
            _ pattern: String,
            color: NSColor,
            storage: NSTextStorage,
            source: String,
            range: NSRange,
            options: NSRegularExpression.Options = []
        ) {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in expression.matches(in: source, range: range) {
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }

        private func highlightingRange(for source: NSString, in textView: NSTextView) -> NSRange {
            let full = NSRange(location: 0, length: source.length)
            guard source.length > 80_000,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else { return full }
            let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: scrollView.contentView.bounds, in: textContainer)
            let visibleCharacterRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
            let start = max(0, visibleCharacterRange.location - 2_000)
            let end = min(source.length, NSMaxRange(visibleCharacterRange) + 2_000)
            guard end > start else { return full }
            return NSRange(location: start, length: end - start)
        }
    }
}


struct LaTeXCompletionState: Equatable {
    var replacementRange: NSRange
    var candidates: [LaTeXCompletionCandidate]
    var selectedIndex: Int = 0
    var argumentCommand: String? = nil
}

final class LaTeXCompletionOverlayView: NSView {
    private(set) var candidates: [LaTeXCompletionCandidate] = []
    private(set) var selectedIndex = 0
    private var firstVisibleIndex = 0
    var palette = SourceEditorPalette(theme: .light, appearance: NSApp.effectiveAppearance) {
        didSet { needsDisplay = true }
    }
    var isShowing: Bool { !isHidden && !candidates.isEmpty }
    var onPick: ((Int) -> Void)?

    private let rowHeight: CGFloat = 27
    private let maxRows = 12
    private let overlayWidth: CGFloat = 390

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { isShowing ? self : nil }

    func show(candidates: [LaTeXCompletionCandidate], selectedIndex: Int, anchor: NSRect, palette: SourceEditorPalette) {
        self.candidates = candidates
        self.selectedIndex = min(max(0, selectedIndex), max(0, self.candidates.count - 1))
        ensureSelectionVisible()
        self.palette = palette
        let rows = max(1, min(maxRows, self.candidates.count))
        let height = CGFloat(rows) * rowHeight + 10
        let containerBounds = superview?.bounds ?? NSRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let maxX = max(8, containerBounds.maxX - overlayWidth - 8)
        let x = min(max(8, anchor.minX), maxX)
        let belowY = anchor.maxY + 5
        let aboveY = anchor.minY - height - 5
        let y = belowY + height <= containerBounds.maxY ? belowY : max(8, aboveY)
        frame = NSRect(x: x, y: y, width: overlayWidth, height: height)
        isHidden = self.candidates.isEmpty
        needsDisplay = true
    }

    func hide() {
        candidates = []
        selectedIndex = 0
        firstVisibleIndex = 0
        isHidden = true
        needsDisplay = true
    }

    func moveSelection(delta: Int) {
        guard !candidates.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + candidates.count) % candidates.count
        ensureSelectionVisible()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isShowing else { return }
        let point = convert(event.locationInWindow, from: nil)
        let visibleCandidates = visibleCandidateSlice()
        guard !visibleCandidates.isEmpty else { return }
        let row = Int(max(0, min(CGFloat(visibleCandidates.count - 1), floor((point.y - 5) / rowHeight))))
        let absoluteIndex = firstVisibleIndex + row
        selectedIndex = min(max(0, absoluteIndex), candidates.count - 1)
        ensureSelectionVisible()
        needsDisplay = true
        onPick?(selectedIndex)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isShowing else { return }
        let background = NSColor.windowBackgroundColor.withAlphaComponent(0.98)
        let border = NSColor.separatorColor.withAlphaComponent(0.75)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        background.setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = 1
        path.stroke()

        for (offset, candidate) in visibleCandidateSlice().enumerated() {
            let index = firstVisibleIndex + offset
            let row = NSRect(x: 5, y: 5 + CGFloat(offset) * rowHeight, width: bounds.width - 10, height: rowHeight)
            if index == selectedIndex {
                NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: row.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5).fill()
            }
            draw(candidate: candidate, in: row, selected: index == selectedIndex)
        }
        drawScrollIndicatorIfNeeded()
    }

    private func visibleCandidateSlice() -> ArraySlice<LaTeXCompletionCandidate> {
        guard !candidates.isEmpty else { return [] }
        let start = min(max(0, firstVisibleIndex), max(0, candidates.count - 1))
        let end = min(candidates.count, start + maxRows)
        return candidates[start..<end]
    }

    private func ensureSelectionVisible() {
        guard !candidates.isEmpty else {
            firstVisibleIndex = 0
            return
        }
        selectedIndex = min(max(0, selectedIndex), candidates.count - 1)
        if selectedIndex < firstVisibleIndex {
            firstVisibleIndex = selectedIndex
        } else if selectedIndex >= firstVisibleIndex + maxRows {
            firstVisibleIndex = selectedIndex - maxRows + 1
        }
        firstVisibleIndex = min(max(0, firstVisibleIndex), max(0, candidates.count - maxRows))
    }

    private func drawScrollIndicatorIfNeeded() {
        guard candidates.count > maxRows else { return }
        let track = NSRect(x: bounds.maxX - 7, y: 8, width: 3, height: max(8, bounds.height - 16))
        NSColor.separatorColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
        let visibleFraction = CGFloat(maxRows) / CGFloat(candidates.count)
        let thumbHeight = max(12, track.height * visibleFraction)
        let maxFirst = max(1, candidates.count - maxRows)
        let progress = CGFloat(firstVisibleIndex) / CGFloat(maxFirst)
        let thumbY = track.minY + (track.height - thumbHeight) * progress
        let thumb = NSRect(x: track.minX, y: thumbY, width: track.width, height: thumbHeight)
        NSColor.secondaryLabelColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: 1.5, yRadius: 1.5).fill()
    }

    private func draw(candidate: LaTeXCompletionCandidate, in row: NSRect, selected: Bool) {
        let insertionAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .medium),
            .foregroundColor: selected ? NSColor.controlAccentColor : palette.command
        ]
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let categoryAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let insertion = NSAttributedString(string: candidate.insertion, attributes: insertionAttributes)
        let detail = NSAttributedString(string: candidate.detail, attributes: detailAttributes)
        let category = NSAttributedString(string: candidate.category.uppercased(), attributes: categoryAttributes)
        insertion.draw(in: NSRect(x: row.minX + 8, y: row.minY + 5, width: 190, height: 17))
        detail.draw(in: NSRect(x: row.minX + 205, y: row.minY + 5, width: 120, height: 17))
        category.draw(in: NSRect(x: row.maxX - 48, y: row.minY + 6, width: 42, height: 15))
    }
}

final class SourceGlyphOverlayView: NSView {
    weak var textView: NSTextView?
    var palette: SourceEditorPalette
    var findRanges: [NSRange] = [] {
        didSet { needsDisplay = true }
    }
    var activeFindRange: NSRange? {
        didSet { needsDisplay = true }
    }
    private(set) var lastSelectionRectCount = 0
    private(set) var lastFindHighlightRectCount = 0
    private(set) var lastCaretRect: NSRect?
    private(set) var lastPaintedSelection = NSRange(location: NSNotFound, length: 0)
    private let caretLayer = CALayer()
    var caretBlinkAnimationActive: Bool { caretLayer.animation(forKey: "SourceLeafCaretBlink") != nil }

    init(textView: NSTextView, palette: SourceEditorPalette) {
        self.textView = textView
        self.palette = palette
        super.init(frame: .zero)
        autoresizingMask = []
        wantsLayer = true
        layer?.isGeometryFlipped = true
        caretLayer.isHidden = true
        caretLayer.actions = ["bounds": NSNull(), "position": NSNull(), "backgroundColor": NSNull(), "hidden": NSNull()]
        layer?.addSublayer(caretLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            caretLayer.removeAllAnimations()
            caretLayer.isHidden = true
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func selectionDidChange() {
        restartCaretBlink()
        needsDisplay = true
        lastPaintedSelection = textView?.selectedRange() ?? NSRange(location: NSNotFound, length: 0)
    }

    func restartCaretBlink() {
        caretLayer.removeAnimation(forKey: "SourceLeafCaretBlink")
        if !caretLayer.isHidden { installCaretBlinkAnimation() }
    }

    func synchronizeFrame() {
        guard let clipView = textView?.enclosingScrollView?.contentView,
              let superview else { return }
        frame = clipView.convert(clipView.bounds, to: superview)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let scrollView = textView.enclosingScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let visible = scrollView.contentView.bounds
        let origin = NSPoint(
            x: textView.textContainerOrigin.x - visible.minX,
            y: textView.textContainerOrigin.y - visible.minY
        )
        lastSelectionRectCount = 0
        lastFindHighlightRectCount = 0
        lastCaretRect = nil
        caretLayer.isHidden = true
        caretLayer.removeAnimation(forKey: "SourceLeafCaretBlink")
        let selectedRange = textView.selectedRange()
        lastPaintedSelection = selectedRange
        drawFindHighlights(
            layoutManager: layoutManager,
            textContainer: textContainer,
            visible: visible,
            origin: origin
        )
        if selectedRange.length == 0,
           textView.window?.firstResponder === textView,
           let caret = caretRect(
               at: selectedRange.location,
               textView: textView,
               layoutManager: layoutManager,
               textContainer: textContainer,
               origin: origin
           ) {
            lastCaretRect = caret
            caretLayer.frame = caret
            caretLayer.backgroundColor = palette.caret.cgColor
            caretLayer.isHidden = false
            installCaretBlinkAnimation()
        }
    }

    private func drawFindHighlights(
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        visible: NSRect,
        origin: NSPoint
    ) {
        guard !findRanges.isEmpty, let textView else { return }
        let stringLength = (textView.string as NSString).length
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        let visibleCharacterRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        for range in findRanges {
            let clamped = NSIntersectionRange(range, NSRange(location: 0, length: stringLength))
            guard clamped.length > 0,
                  NSIntersectionRange(clamped, visibleCharacterRange).length > 0 else { continue }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: clamped, actualCharacterRange: nil)
            let active = activeFindRange == range
            let fill = active
                ? NSColor.systemYellow.withAlphaComponent(0.50)
                : NSColor.systemYellow.withAlphaComponent(0.34)
            let stroke = active
                ? NSColor.systemOrange
                : NSColor.systemOrange.withAlphaComponent(0.65)
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                var highlight = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -1.5, dy: -1)
                highlight.size.height = max(2, highlight.height)
                let path = NSBezierPath(roundedRect: highlight, xRadius: 3, yRadius: 3)
                fill.setFill()
                path.fill()
                stroke.setStroke()
                path.lineWidth = active ? 1.3 : 1.0
                path.stroke()
                self.lastFindHighlightRectCount += 1
            }
        }
    }

    private func installCaretBlinkAnimation() {
        guard caretLayer.animation(forKey: "SourceLeafCaretBlink") == nil else { return }
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1, 1, 0, 0]
        animation.keyTimes = [0, 0.49, 0.5, 1]
        animation.duration = 1.06
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        caretLayer.add(animation, forKey: "SourceLeafCaretBlink")
    }

    private func caretRect(
        at characterIndex: Int,
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        origin: NSPoint
    ) -> NSRect? {
        let length = (textView.string as NSString).length
        if characterIndex < length {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            guard glyphRect.height > 0 else { return nil }
            return NSRect(x: glyphRect.minX + origin.x, y: glyphRect.minY + origin.y, width: 2, height: glyphRect.height)
        }
        let extra = layoutManager.extraLineFragmentRect
        guard extra.height > 0 else { return nil }
        return NSRect(x: extra.minX + origin.x, y: extra.minY + origin.y, width: 2, height: extra.height)
    }
}

extension Notification.Name {
    static let sourceLeafShowFind = Notification.Name("SourceLeaf.showFindAndReplace")
}

final class SourceEditorContainerView: NSView {
    private let editorScrollView: NSScrollView
    private let editorTextView: NSTextView
    weak var glyphOverlay: SourceGlyphOverlayView?
    weak var completionOverlay: LaTeXCompletionOverlayView?
    var backgroundColor: NSColor {
        didSet {
            layer?.backgroundColor = backgroundColor.cgColor
            needsDisplay = true
        }
    }

    init(scrollView: NSScrollView, textView: NSTextView, backgroundColor: NSColor) {
        editorScrollView = scrollView
        editorTextView = textView
        self.backgroundColor = backgroundColor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let width = max(editorScrollView.contentSize.width, 1)
        guard width.isFinite else { return }
        if abs(editorTextView.frame.width - width) > 0.5 {
            editorTextView.setFrameSize(NSSize(width: width, height: max(editorTextView.frame.height, 1)))
        }
        editorTextView.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        if let textContainer = editorTextView.textContainer {
            textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textContainer.widthTracksTextView = true
            editorTextView.layoutManager?.ensureLayout(for: textContainer)
        }
        glyphOverlay?.synchronizeFrame()
        glyphOverlay?.needsDisplay = true
        if completionOverlay?.isShowing == true { completionOverlay?.needsDisplay = true }
        editorTextView.setNeedsDisplay(editorTextView.visibleRect)
    }
}

struct SourceEditorPalette {
    let text: NSColor
    let background: NSColor
    let command: NSColor
    let comment: NSColor
    let optionalArgument: NSColor
    let math: NSColor
    let brace: NSColor
    let selectionBackground: NSColor
    let selectionText: NSColor
    let caret: NSColor
    let gutterBackground: NSColor
    let gutterText: NSColor

    init(theme: EditorTheme, appearance: NSAppearance) {
        let dark = theme.isDark(for: appearance)
        if dark {
            text = NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1)
            background = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1)
            command = NSColor(srgbRed: 0.38, green: 0.68, blue: 1.00, alpha: 1)
            comment = NSColor(srgbRed: 0.35, green: 0.78, blue: 0.43, alpha: 1)
            optionalArgument = NSColor(srgbRed: 0.38, green: 0.78, blue: 0.82, alpha: 1)
            math = NSColor(srgbRed: 0.80, green: 0.55, blue: 0.95, alpha: 1)
            brace = NSColor(srgbRed: 1.00, green: 0.64, blue: 0.27, alpha: 1)
            selectionBackground = NSColor(srgbRed: 0.18, green: 0.42, blue: 0.72, alpha: 1)
            selectionText = text
            caret = NSColor(srgbRed: 0.98, green: 0.76, blue: 0.25, alpha: 1)
            gutterBackground = NSColor(srgbRed: 0.075, green: 0.085, blue: 0.10, alpha: 1)
            gutterText = NSColor(srgbRed: 0.57, green: 0.60, blue: 0.66, alpha: 1)
        } else {
            text = NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1)
            background = NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1)
            command = NSColor(srgbRed: 0.05, green: 0.18, blue: 0.95, alpha: 1)
            comment = NSColor(srgbRed: 0.30, green: 0.61, blue: 0.47, alpha: 1)
            optionalArgument = NSColor(srgbRed: 0.19, green: 0.55, blue: 0.62, alpha: 1)
            math = NSColor(srgbRed: 0.55, green: 0.20, blue: 0.72, alpha: 1)
            brace = NSColor(srgbRed: 0.92, green: 0.42, blue: 0.00, alpha: 1)
            selectionBackground = NSColor(srgbRed: 0.70, green: 0.83, blue: 0.97, alpha: 1)
            selectionText = text
            caret = NSColor(srgbRed: 0.05, green: 0.18, blue: 0.95, alpha: 1)
            gutterBackground = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
            gutterText = NSColor(srgbRed: 0.36, green: 0.37, blue: 0.40, alpha: 1)
        }
    }
}

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    private(set) var lastDrawnLines: [Int] = []
    private(set) var scrollChangeCount = 0
    var backgroundColor = NSColor.textBackgroundColor
    var numberColor = NSColor.secondaryLabelColor

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    func scrollPositionDidChange() {
        scrollChangeCount += 1
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        backgroundColor.setFill()
        rect.fill()

        let visible = textView.enclosingScrollView?.contentView.bounds ?? textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let source = textView.string
        let visibleLines = SourceLineMap.visibleLineStarts(in: source, utf16Range: characterRange)
        lastDrawnLines = visibleLines.map(\.line)
        for item in visibleLines {
            guard item.utf16Location < (source as NSString).length else { continue }
            let glyph = layoutManager.glyphIndexForCharacter(at: item.utf16Location)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = fragment.minY - visible.minY + textView.textContainerOrigin.y
            let string = "\(item.line)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: numberColor
            ]
            let size = string.size(withAttributes: attributes)
            string.draw(at: NSPoint(x: ruleThickness - size.width - 7, y: y + 2), withAttributes: attributes)
        }
    }
}
