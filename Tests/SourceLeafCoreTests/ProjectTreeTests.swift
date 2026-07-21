import Foundation
import Testing
@testable import SourceLeafCore

@Test func projectTreePreservesFolderHierarchyAndFileKinds() {
    let root = URL(fileURLWithPath: "/tmp/project")
    let files = [
        ProjectFile(relativePath: "main.tex", url: root.appendingPathComponent("main.tex"), kind: .tex),
        ProjectFile(relativePath: "figures/result.png", url: root.appendingPathComponent("figures/result.png"), kind: .image),
        ProjectFile(relativePath: "sections/method.tex", url: root.appendingPathComponent("sections/method.tex"), kind: .tex),
        ProjectFile(relativePath: "sections/sub/appendix.tex", url: root.appendingPathComponent("sections/sub/appendix.tex"), kind: .tex)
    ]

    let tree = ProjectIndexer.tree(files: files)
    #expect(tree.map(\.name) == ["figures", "sections", "main.tex"])
    let sections = tree.first { $0.name == "sections" }
    #expect(sections?.children?.map(\.name) == ["sub", "method.tex"])
    #expect(sections?.children?.first?.children?.first?.file?.relativePath == "sections/sub/appendix.tex")
    #expect(tree.first?.children?.first?.file?.kind == .image)
}

@Test func sourceLineMapFindsLogicalLinesInEitherScrollDirection() {
    let source = (1...200).map { "line \($0)" }.joined(separator: "\n")
    let location150 = SourceLineMap.utf16Location(in: source, line: 150)
    let rangeNearBottom = NSRange(location: location150, length: 120)
    #expect(SourceLineMap.visibleLineStarts(in: source, utf16Range: rangeNearBottom).first?.line == 150)

    let location40 = SourceLineMap.utf16Location(in: source, line: 40)
    let rangeAfterScrollingUp = NSRange(location: location40, length: 120)
    let visible = SourceLineMap.visibleLineStarts(in: source, utf16Range: rangeAfterScrollingUp)
    #expect(visible.first?.line == 40)
    #expect(visible.map(\.line) == visible.map(\.line).sorted())
}
