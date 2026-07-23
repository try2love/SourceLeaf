import AppKit
import Foundation
import SourceLeafCore
import SwiftUI
import Testing
@testable import SourceLeafApp

@MainActor
@Test func nestedProjectOutlineNavigatesAcrossSourceFiles() throws {
    guard let fixturesPath = ProcessInfo.processInfo.environment["SOURCELEAF_BOUNDARY_PROJECTS"] else { return }
    let fixtures = URL(fileURLWithPath: fixturesPath, isDirectory: true)
    let model = try isolatedModel(named: "nested")
    model.openProject(fixtures.appendingPathComponent("多文件论文", isDirectory: true))

    #expect(model.configuration.rootDocument == "main.tex")
    let details = try #require(model.outline.first { $0.relativePath == "sections/deep/details.tex" })
    #expect(details.title == "Implementation Details")
    model.jumpToOutline(details)
    #expect(model.selectedFile?.relativePath == "sections/deep/details.tex")
    #expect(model.selectedRange.location == SourceLineMap.utf16Location(in: model.sourceText, line: details.line))
}

@MainActor
@Test func projectWithoutDocumentClassDoesNotInventARootDocument() throws {
    guard let fixturesPath = ProcessInfo.processInfo.environment["SOURCELEAF_BOUNDARY_PROJECTS"] else { return }
    let fixtures = URL(fileURLWithPath: fixturesPath, isDirectory: true)
    let model = try isolatedModel(named: "missing-root")
    model.openProject(fixtures.appendingPathComponent("缺少主文档", isDirectory: true))

    #expect(model.selectedFile?.relativePath == "notes.tex")
    #expect(model.configuration.rootDocument == nil)
    model.compile()
    #expect(model.lastError == L10n.text("error.rootDocumentMissing"))
}

@MainActor
@Test func imageOnlyProjectRoutesRasterAndVectorFilesToPreview() throws {
    guard let fixturesPath = ProcessInfo.processInfo.environment["SOURCELEAF_BOUNDARY_PROJECTS"] else { return }
    let fixtures = URL(fileURLWithPath: fixturesPath, isDirectory: true)
    let model = try isolatedModel(named: "images")
    model.openProject(fixtures.appendingPathComponent("图片格式", isDirectory: true))

    let images = model.projectFiles.filter { $0.kind == .image }
    #expect(Set(images.map(\.relativePath)) == ["portrait.jpg", "vector.svg"])
    for image in images {
        model.openFile(image)
        #expect(model.selectedImageFile?.relativePath == image.relativePath)
    }
}

@MainActor
@Test func imagePanelLoadsTheSelectedSVGIntoAZoomablePreview() throws {
    guard let fixturesPath = ProcessInfo.processInfo.environment["SOURCELEAF_BOUNDARY_PROJECTS"] else { return }
    let fixtures = URL(fileURLWithPath: fixturesPath, isDirectory: true)
    let model = try isolatedModel(named: "image-preview")
    model.openProject(fixtures.appendingPathComponent("图片格式", isDirectory: true))
    let svg = try #require(model.projectFiles.first { $0.relativePath == "vector.svg" })
    model.openFile(svg)

    let hostingView = NSHostingView(
        rootView: ImagePanel()
            .environmentObject(model)
            .frame(width: 720, height: 520)
    )
    hostingView.frame = NSRect(x: 0, y: 0, width: 720, height: 520)
    hostingView.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    let preview = try #require(findZoomableImagePreview(in: hostingView))
    #expect(preview.loadedURL == svg.url)
    #expect(preview.allowsMagnification)
    #expect(preview.minMagnification == 0.1)
    #expect(preview.maxMagnification == 8)
    #expect(ZoomableImageScrollView.zoomedScale(from: 1, scrollingDeltaY: 1) > 1)
    preview.setZoomScale(0.1)
    preview.layoutSubtreeIfNeeded()
    #expect(preview.contentInsets.left > 0 || preview.contentInsets.top > 0)
}

@MainActor
@Test func authorPhotoSurvivesRepeatedWindowLayoutWithoutCrashing() throws {
    guard let projectPath = ProcessInfo.processInfo.environment["SOURCELEAF_REAL_PROJECT"] else { return }
    let project = URL(fileURLWithPath: projectPath, isDirectory: true)
    let model = try isolatedModel(named: "author-photo-crash")
    model.openProject(project)
    let photo = try #require(model.projectFiles.first { $0.relativePath == "figures/author/LiweiLiu.jpg" })
    model.openFile(photo)
    let hostingView = NSHostingView(
        rootView: WorkspaceView()
            .environmentObject(model)
            .frame(width: 1180, height: 760)
    )
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
        styleMask: [.titled, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    defer {
        window.contentView = nil
        window.close()
    }
    window.makeKeyAndOrderFront(nil)

    for width in stride(from: 1180.0, through: 920.0, by: -20.0) {
        window.setContentSize(NSSize(width: width, height: 760))
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    }

    let preview = try #require(findZoomableImagePreview(in: hostingView))
    #expect(preview.loadedURL == photo.url)
    #expect(model.layout.selected[.center] == .image)
}

@MainActor
@Test func sourceAndImageTabsSwitchWithoutDiscardingEitherDocument() throws {
    guard let fixturesPath = ProcessInfo.processInfo.environment["SOURCELEAF_BOUNDARY_PROJECTS"] else { return }
    let project = URL(fileURLWithPath: fixturesPath, isDirectory: true)
        .appendingPathComponent("多文件论文", isDirectory: true)
    let model = try isolatedModel(named: "source-image-tabs")
    model.openProject(project)
    let source = try #require(model.projectFiles.first { $0.kind == .tex })
    let image = try #require(model.projectFiles.first { $0.kind == .image })

    model.openFile(image)
    model.openFile(source)

    #expect(model.selectedFile?.relativePath == source.relativePath)
    #expect(model.selectedImageFile?.relativePath == image.relativePath)
    #expect(model.layout.zones[.center]?.contains(.source) == true)
    #expect(model.layout.zones[.center]?.contains(.image) == true)
    #expect(model.layout.selected[.center] == .source)

    model.selectPanel(.image, in: .center)
    #expect(model.layout.selected[.center] == .image)
    #expect(model.selectedImageFile?.relativePath == image.relativePath)
    model.selectPanel(.source, in: .center)
    #expect(model.layout.selected[.center] == .source)
    #expect(model.selectedImageFile?.relativePath == image.relativePath)
}

@MainActor
@Test func invalidUTF8SourceFailsSafelyWithoutShowingStaleText() throws {
    guard let fixturesPath = ProcessInfo.processInfo.environment["SOURCELEAF_BOUNDARY_PROJECTS"] else { return }
    let project = URL(fileURLWithPath: fixturesPath, isDirectory: true)
        .appendingPathComponent("非UTF8源码", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data([0xff, 0xfe, 0x00, 0x5c, 0x00]).write(to: project.appendingPathComponent("invalid.tex"), options: .atomic)
    let model = try isolatedModel(named: "invalid-utf8")
    model.openProject(project)

    #expect(model.selectedFile == nil)
    #expect(model.sourceText.isEmpty)
    #expect(model.lastError != nil)
}

@MainActor
@Test func syncTeXNavigatesFromNestedSourceToPDFAndBack() async throws {
    guard let fixturesPath = ProcessInfo.processInfo.environment["SOURCELEAF_BOUNDARY_PROJECTS"] else { return }
    let project = URL(fileURLWithPath: fixturesPath, isDirectory: true)
        .appendingPathComponent("多文件论文", isDirectory: true)
    let model = try isolatedModel(named: "synctex-navigation")
    model.openProject(project)
    let details = try #require(model.projectFiles.first { $0.relativePath == "sections/deep/details.tex" })
    model.openFile(details)
    model.syncTeXDocument = try await SyncTeXDocument.load(
        from: project.appendingPathComponent("输出/main.synctex.gz")
    )

    model.locateSourceInPDF()
    let target = try #require(model.pdfNavigationTarget)
    #expect(target.pageIndex == 0)
    model.openFile(try #require(model.projectFiles.first { $0.relativePath == "main.tex" }))
    model.locatePDFPointInSource(
        pageIndex: target.pageIndex,
        x: target.x,
        yFromTop: target.yFromTop,
        selectedText: "Implementation"
    )
    #expect(model.selectedFile?.relativePath == "sections/deep/details.tex")
    #expect(SourceLineMap.lineNumber(in: model.sourceText, utf16Location: model.selectedRange.location) == 1)
    #expect((model.sourceText as NSString).substring(with: model.selectedRange) == "Implementation")
    #expect(model.layout.selected[model.layout.zone(containing: .source) ?? .center] == .source)
}

@MainActor
private func isolatedModel(named name: String) throws -> AppModel {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SourceLeaf-boundary-state-\(name)-\(UUID().uuidString)", isDirectory: true)
    let defaults = try #require(UserDefaults(suiteName: "SourceLeaf.boundary.\(name).\(UUID().uuidString)"))
    return AppModel(restoreLastProject: false, supportDirectory: root, defaults: defaults)
}

@MainActor
private func findZoomableImagePreview(in view: NSView) -> ZoomableImageScrollView? {
    if let preview = view as? ZoomableImageScrollView { return preview }
    for child in view.subviews {
        if let result = findZoomableImagePreview(in: child) { return result }
    }
    return nil
}
