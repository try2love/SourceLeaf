import Foundation
import Testing
@testable import SourceLeafCore

@Test func realMutedRAGProjectIndexesLikeAUsableWorkspace() throws {
    guard let path = ProcessInfo.processInfo.environment["SOURCELEAF_REAL_PROJECT"] else { return }
    let root = URL(fileURLWithPath: path, isDirectory: true)

    let files = ProjectIndexer.discoverFiles(root: root)
    let detectedRoot = ProjectIndexer.detectRootDocument(files: files)
    let tree = ProjectIndexer.tree(files: files)
    let source = try String(contentsOf: root.appendingPathComponent("MutedRAG.tex"), encoding: .utf8)
    let outline = ProjectIndexer.outline(for: source)

    #expect(detectedRoot?.relativePath == "MutedRAG.tex")
    #expect(files.contains { $0.relativePath == "reference.bib" && $0.kind == .bibliography })
    #expect(files.contains { $0.relativePath == "figures/overview.png" && $0.kind == .image })
    #expect(files.contains { $0.relativePath == "figures/author/PanSuo.jpg" && $0.kind == .image })
    #expect(tree.first { $0.name == "figures" }?.children?.contains { $0.name == "author" } == true)
    #expect(outline.contains { $0.title == "Introduction" && $0.line == 105 })
    #expect(outline.contains { $0.title == "Method" && $0.line == 229 })
    #expect(outline.contains { $0.title == "Defenses" && $0.line == 686 })
    #expect(outline.count >= 20)
}
