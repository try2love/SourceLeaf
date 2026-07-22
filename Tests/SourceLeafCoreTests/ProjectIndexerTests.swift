import Foundation
import Testing
@testable import SourceLeafCore

@Test func projectPDFsHaveADedicatedPreviewKind() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sourceleaf-pdf-kind-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("%PDF-1.4".utf8).write(to: root.appendingPathComponent("paper.pdf"))

    let file = try #require(ProjectIndexer.discoverFiles(root: root).first)
    #expect(file.kind == .pdf)
}

@Test func buildsDocumentOutlineAndSectionContext() {
    let source = """
    Intro
    \\section{Method}
    Method body.
    \\subsection{Details}
    Details body.
    \\section{Results}
    Results body.
    """
    let outline = ProjectIndexer.outline(for: source)
    #expect(outline.map(\.title) == ["Method", "Details", "Results"])
    let context = ProjectIndexer.sectionContext(source: source, containingLine: 5)
    #expect(context.contains("Details body."))
    #expect(!context.contains("Results body."))
}

@Test func outlineKeepsTheOwningSourceFileForCrossFileNavigation() {
    let source = "\\section{Implementation}\nBody"
    let outline = ProjectIndexer.outline(for: source, relativePath: "sections/deep/details.tex")
    #expect(outline.first?.title == "Implementation")
    #expect(outline.first?.relativePath == "sections/deep/details.tex")
    #expect(outline.first?.line == 1)
}

@Test func documentOutlineTreePreservesHeadingHierarchyAndFileBoundaries() throws {
    let first = ProjectIndexer.outline(
        for: "\\section{Method}\n\\subsection{Details}\n\\subsubsection{Proof}\n\\section{Results}",
        relativePath: "main.tex"
    )
    let second = ProjectIndexer.outline(
        for: "\\subsection{Independent appendix detail}\n\\paragraph{Note}",
        relativePath: "appendix.tex"
    )

    let tree = ProjectIndexer.outlineTree(from: first + second)
    #expect(tree.count == 3)
    #expect(tree[0].item.title == "Method")
    #expect(tree[0].children.map(\.item.title) == ["Details"])
    #expect(tree[0].children[0].children.map(\.item.title) == ["Proof"])
    #expect(tree[1].item.title == "Results")
    #expect(tree[2].item.title == "Independent appendix detail")
    #expect(tree[2].children.map(\.item.title) == ["Note"])
}

@Test func nearbyContextIsBounded() throws {
    let source = (1...100).map { "line \($0)" }.joined(separator: "\n")
    let target = try SourceTargetService.target(in: source, relativePath: "main.tex", startLine: 50, endLine: 50)
    let context = ProjectIndexer.nearbyContext(source: source, target: target, radius: 2)
    #expect(context.contains("line 48"))
    #expect(context.contains("line 52"))
    #expect(!context.contains("line 47\n"))
}

@Test func sourceLineMapSelectsThePDFWordOnTheLocatedLine() throws {
    let source = "First line\nImplementation details and evidence.\nFinal line"
    let range = try #require(SourceLineMap.utf16Range(
        of: "Implementation",
        in: source,
        line: 2
    ))
    #expect((source as NSString).substring(with: range) == "Implementation")
    #expect(SourceLineMap.utf16Range(of: "First", in: source, line: 2) == nil)
}
