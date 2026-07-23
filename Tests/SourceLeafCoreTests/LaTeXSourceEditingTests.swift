import Foundation
import Testing
@testable import SourceLeafCore

@Test func latexFormattingWrapsAUTF16Selection() {
    let source = "前缀😀important后缀"
    let range = (source as NSString).range(of: "important")
    let edit = LaTeXSourceFormatter.edit(command: .bold, source: source, selection: range)

    #expect(edit.replacementRange == range)
    #expect(edit.replacement == "\\textbf{important}")
    #expect(edit.resultingSelection == NSRange(location: range.location + 8, length: 9))
}

@Test func latexFormattingInsertsSelectablePlaceholders() {
    let heading = LaTeXSourceFormatter.edit(
        command: .subsection,
        source: "abc",
        selection: NSRange(location: 3, length: 0)
    )
    #expect(heading.replacement == "\\subsection{Title}")
    #expect(heading.resultingSelection == NSRange(location: 15, length: 5))

    let math = LaTeXSourceFormatter.edit(
        command: .displayMath,
        source: "",
        selection: NSRange(location: 0, length: 0)
    )
    #expect(math.replacement == "\\[\nformula\n\\]")
    #expect(math.resultingSelection == NSRange(location: 3, length: 7))
}

@Test func latexFormattingUsesCorrectGroupingAndListSyntax() {
    let sized = LaTeXSourceFormatter.edit(
        command: .small,
        source: "result",
        selection: NSRange(location: 0, length: 6)
    )
    #expect(sized.replacement == "{\\small result}")

    let list = LaTeXSourceFormatter.edit(
        command: .itemize,
        source: "first\nsecond",
        selection: NSRange(location: 0, length: 12)
    )
    #expect(list.replacement == "\\begin{itemize}\n  \\item first\n  \\item second\n\\end{itemize}")
}

@Test func latexFormattingTogglesAnExistingWrapperWithoutNesting() {
    let source = "Prefix \\textbf{important} suffix"
    let inner = (source as NSString).range(of: "important")
    let edit = LaTeXSourceFormatter.edit(command: .bold, source: source, selection: inner)

    #expect(edit.replacementRange == (source as NSString).range(of: "\\textbf{important}"))
    #expect(edit.replacement == "important")
    #expect(edit.resultingSelection == NSRange(location: inner.location - 8, length: inner.length))
}

@Test func latexFormattingProvidesProfessionalTableAndFigureTemplates() {
    let table = LaTeXSourceFormatter.edit(
        command: .table,
        source: "",
        selection: NSRange(location: 0, length: 0)
    )
    #expect(table.replacement.contains("\\begin{tabular}"))
    #expect(table.replacement.contains("\\caption{"))
    #expect(table.replacement.contains("Column 1 & Column 2 \\\\\n"))

    let figure = LaTeXSourceFormatter.edit(
        command: .figure,
        source: "",
        selection: NSRange(location: 0, length: 0)
    )
    #expect(figure.replacement.contains("\\includegraphics"))
    #expect(figure.replacement.contains("figures/image.png"))
}

@Test func latexFigureTemplateCanUseAProjectImagePath() {
    let edit = LaTeXSourceFormatter.edit(
        command: .figure,
        source: "",
        selection: NSRange(location: 0, length: 0),
        argument: "figures/results/overview.pdf"
    )

    #expect(edit.replacement.contains("\\includegraphics[width=\\linewidth]{figures/results/overview.pdf}"))
    #expect(edit.replacement.contains("\\caption{Caption}"))
    #expect((edit.replacement as NSString).substring(with: edit.resultingSelection) == "Caption")
}
