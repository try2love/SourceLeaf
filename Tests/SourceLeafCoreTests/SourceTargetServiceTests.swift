import Foundation
import Testing
@testable import SourceLeafCore

@Test func selectionTargetCapturesLinesAndRejectsStaleText() throws {
    let source = "first\nsecond line\nthird"
    let range = (source as NSString).range(of: "second line")
    let target = try SourceTargetService.target(in: source, relativePath: "main.tex", utf16Range: range)

    #expect(target.startLine == 2)
    #expect(target.endLine == 2)
    #expect(target.originalText == "second line")

    let proposal = ProposedReplacement(targetID: target.id, replacement: "replacement")
    let updated = try SourceTargetService.apply(proposal: proposal, targets: [target], currentText: source)
    #expect(updated == "first\nreplacement\nthird")

    #expect(throws: SourceTargetError.staleTarget) {
        try SourceTargetService.apply(
            proposal: proposal,
            targets: [target],
            currentText: "first\nchanged text\nthird"
        )
    }
}

@Test func lineTargetUsesOneBasedInclusiveLines() throws {
    let source = "a\nbb\nccc\ndddd"
    let target = try SourceTargetService.target(
        in: source,
        relativePath: "sections/method.tex",
        startLine: 2,
        endLine: 3
    )
    #expect(target.originalText == "bb\nccc")
    #expect(target.utf16Location == 2)
}

@Test func parsesNaturalAndExplicitLineReferences() {
    #expect(SourceTargetService.parseLineReferences(in: "修改 120 到 135 行") == [
        ParsedLineReference(relativePath: nil, startLine: 120, endLine: 135)
    ])
    #expect(SourceTargetService.parseLineReferences(in: "revise sections/method.tex:80-96") == [
        ParsedLineReference(relativePath: "sections/method.tex", startLine: 80, endLine: 96)
    ])
}

@Test func rejectsPathsOutsideProject() throws {
    let root = URL(fileURLWithPath: "/tmp/project")
    #expect(throws: SourceTargetError.pathOutsideProject) {
        try SourceTargetService.validatedURL(relativePath: "../secret.tex", projectRoot: root)
    }
}
