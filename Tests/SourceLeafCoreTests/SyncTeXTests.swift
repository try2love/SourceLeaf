import Foundation
import Testing
@testable import SourceLeafCore

private let syncTeXFixture = """
SyncTeX Version:1
Input:1:/tmp/paper/main.tex
Input:13:/tmp/paper/sections/introduction.tex
Input:15:/tmp/paper/sections/deep/details.tex
Output:pdf
Magnification:1000
Unit:1
X Offset:0
Y Offset:0
Content:
{1
(1,10:8799519,15060045:22609920,545784,160431
(13,1:8799519,17883663:1475031,619079,0
g13,3:12010128,19319753
(15,1:8799519,29503300:1918108,515899,0
g15,2:12303074,32548921
}1
Postamble:
"""

@Test func parsesForwardSyncTeXLocationAcrossNestedFiles() throws {
    let index = try SyncTeXDocument(contents: syncTeXFixture)
    let location = try #require(index.pdfLocation(
        sourceURL: URL(fileURLWithPath: "/tmp/paper/sections/deep/details.tex"),
        line: 1
    ))
    #expect(location.pageIndex == 0)
    #expect(abs(location.x - 133.77) < 0.1)
    #expect(abs(location.yFromTop - 448.50) < 0.1)
}

@Test func reverseSyncTeXLocationFindsTheOwningFileAndLine() throws {
    let index = try SyncTeXDocument(contents: syncTeXFixture)
    let location = try #require(index.sourceLocation(
        pageIndex: 0,
        x: 134,
        yFromTop: 448
    ))
    #expect(location.sourceURL.path == "/tmp/paper/sections/deep/details.tex")
    #expect(location.line == 1)
}

@Test func loadsTheRealCompressedMultiFileSyncTeXIndex() async throws {
    guard let fixturesPath = ProcessInfo.processInfo.environment["SOURCELEAF_BOUNDARY_PROJECTS"] else { return }
    let project = URL(fileURLWithPath: fixturesPath, isDirectory: true)
        .appendingPathComponent("多文件论文", isDirectory: true)
    let index = try await SyncTeXDocument.load(
        from: project.appendingPathComponent("输出/main.synctex.gz")
    )
    let detailsURL = project.appendingPathComponent("sections/deep/details.tex")
    let pdfLocation = try #require(index.pdfLocation(sourceURL: detailsURL, line: 1))
    #expect(pdfLocation.pageIndex == 0)
    let sourceLocation = try #require(index.sourceLocation(
        pageIndex: pdfLocation.pageIndex,
        x: pdfLocation.x,
        yFromTop: pdfLocation.yFromTop
    ))
    #expect(sourceLocation.sourceURL.standardizedFileURL == detailsURL.standardizedFileURL)
    #expect(sourceLocation.line == 1)
}
