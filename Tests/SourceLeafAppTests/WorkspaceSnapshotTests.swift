import AppKit
import Foundation
import PDFKit
import SourceLeafCore
import SwiftUI
import Testing
@testable import SourceLeafApp

@MainActor
@Test func applicationModelCanBeIsolatedForVisualTests() throws {
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("SourceLeaf-visual-state-\(UUID().uuidString)", isDirectory: true)
    let defaults = try #require(UserDefaults(suiteName: "SourceLeaf.visual.\(UUID().uuidString)"))
    let model = AppModel(
        restoreLastProject: false,
        supportDirectory: support,
        defaults: defaults
    )

    #expect(model.projectRoot == nil)
}

@MainActor
@Test func explicitChineseLanguageLocalizesEveryRepresentativeSurface() {
    let previous = UserDefaults.standard.object(forKey: L10n.languageDefaultsKey)
    UserDefaults.standard.set(AppLanguage.simplifiedChinese.rawValue, forKey: L10n.languageDefaultsKey)
    defer {
        if let previous { UserDefaults.standard.set(previous, forKey: L10n.languageDefaultsKey) }
        else { UserDefaults.standard.removeObject(forKey: L10n.languageDefaultsKey) }
    }

    #expect(L10n.project == "项目")
    #expect(L10n.compile == "立即编译")
    #expect(L10n.buildLog == "编译日志")
    #expect(L10n.text("status.buildSucceeded") == "编译成功")
    #expect(L10n.text("error.engineUnavailable").contains("LaTeX 引擎"))
}

@MainActor
@Test func sourceEditorLaysOutReadableTextAtItsVisibleWidth() throws {
    let source = "\\documentclass{article}\n\\begin{document}\nVisible LaTeX source\n\\end{document}\n"
    let hostingView = NSHostingView(
        rootView: SourceTextView(
            text: .constant(source),
            selection: .constant(NSRange(location: 0, length: 0)),
            showSelectionButton: false,
            onAskAI: {}
        )
        .frame(width: 640, height: 420)
    )
    hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
    hostingView.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

    let textView = try #require(findSourceTextView(in: hostingView))
    let usedRect = try #require(textView.layoutManager).usedRect(
        for: try #require(textView.textContainer)
    )
    #expect(textView.string == source)
    #expect(textView.frame.width > 500)
    #expect(textView.textContainer?.containerSize.width ?? 0 > 500)
    #expect(usedRect.width > 100)
    #expect(usedRect.height > 40)
}

@MainActor
@Test func pdfPreviewUsesOnePagePerViewport() throws {
    let hostingView = NSHostingView(
        rootView: PDFKitView(
            url: URL(fileURLWithPath: "/tmp/nonexistent.pdf"),
            selection: .constant(""),
            pageIndex: .constant(0),
            pageCount: .constant(0),
            navigationTarget: nil,
            onCommandClick: { _, _, _, _ in }
        )
        .frame(width: 600, height: 700)
    )
    hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 700)
    hostingView.layoutSubtreeIfNeeded()

    let pdfView = try #require(findPDFView(in: hostingView))
    #expect(pdfView.displayMode == .singlePage)
}

@MainActor
@Test func pdfReverseSyncAcceptsDoubleClickAndCommandClick() {
    #expect(NavigablePDFView.shouldTriggerSourceLookup(clickCount: 2, modifierFlags: []))
    #expect(NavigablePDFView.shouldTriggerSourceLookup(clickCount: 1, modifierFlags: [.command]))
    #expect(!NavigablePDFView.shouldTriggerSourceLookup(clickCount: 1, modifierFlags: []))
}

@MainActor
@Test func lineNumberRulerRefreshesWhenScrollingUpFromTheBottom() throws {
    let source = (1...500).map { "line \($0)" }.joined(separator: "\n")
    let hostingView = NSHostingView(
        rootView: SourceTextView(
            text: .constant(source),
            selection: .constant(NSRange(location: 0, length: 0)),
            showSelectionButton: false,
            onAskAI: {}
        )
        .frame(width: 640, height: 420)
    )
    hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
    hostingView.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

    let textView = try #require(findSourceTextView(in: hostingView))
    let scrollView = try #require(textView.enclosingScrollView)
    let ruler = try #require(scrollView.verticalRulerView as? LineNumberRulerView)
    textView.scrollRangeToVisible(NSRange(location: (source as NSString).length - 1, length: 0))
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    let bottomScrollChangeCount = ruler.scrollChangeCount

    let line40 = SourceLineMap.utf16Location(in: source, line: 40)
    textView.scrollRangeToVisible(NSRange(location: line40, length: 0))
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    #expect(ruler.scrollChangeCount > bottomScrollChangeCount)

    let visible = textView.visibleRect
    let glyphs = try #require(textView.layoutManager).glyphRange(
        forBoundingRect: visible,
        in: try #require(textView.textContainer)
    )
    let characters = textView.layoutManager?.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
    let firstLine = characters.flatMap { SourceLineMap.visibleLineStarts(in: source, utf16Range: $0).first?.line }
    #expect(firstLine != nil)
    #expect((firstLine ?? 500) < 80)
}

@MainActor
@Test func realWorkspaceRendersInLightAndDarkAppearances() async throws {
    guard let projectPath = ProcessInfo.processInfo.environment["SOURCELEAF_REAL_PROJECT"],
          let outputPath = ProcessInfo.processInfo.environment["SOURCELEAF_SNAPSHOT_OUTPUT"] else { return }
    let output = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let support = output.appendingPathComponent("状态", isDirectory: true)
    let defaults = try #require(UserDefaults(suiteName: "SourceLeaf.snapshot.\(UUID().uuidString)"))
    defaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: L10n.languageDefaultsKey)
    let standardLanguage = UserDefaults.standard.object(forKey: L10n.languageDefaultsKey)
    UserDefaults.standard.set(AppLanguage.simplifiedChinese.rawValue, forKey: L10n.languageDefaultsKey)
    defer {
        if let standardLanguage {
            UserDefaults.standard.set(standardLanguage, forKey: L10n.languageDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: L10n.languageDefaultsKey)
        }
    }
    let model = AppModel(
        restoreLastProject: false,
        supportDirectory: support,
        defaults: defaults
    )
    model.openProject(URL(fileURLWithPath: projectPath, isDirectory: true))
    model.pdfURL = URL(fileURLWithPath: projectPath)
        .appendingPathComponent("输出/MutedRAG.pdf")
    model.syncTeXDocument = try await SyncTeXDocument.load(
        from: URL(fileURLWithPath: projectPath).appendingPathComponent("输出/MutedRAG.synctex.gz")
    )
    model.buildLog = "note: downloading acmart.cls\nwarning: MutedRAG.tex:169: Overfull \\hbox\nnote: Writing MutedRAG.pdf"
    model.buildPhase = .finished
    model.buildSucceeded = true

    let light = try render(
        WorkspaceView()
            .environmentObject(model)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .environment(\.colorScheme, .light),
        size: NSSize(width: 1440, height: 900)
    )
    let dark = try render(
        WorkspaceView()
            .environmentObject(model)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .environment(\.colorScheme, .dark),
        size: NSSize(width: 1440, height: 900)
    )
    let compact = try render(
        WorkspaceView()
            .environmentObject(model)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .environment(\.colorScheme, .light),
        size: NSSize(width: 1024, height: 700)
    )
    let wide = try render(
        WorkspaceView()
            .environmentObject(model)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .environment(\.colorScheme, .dark),
        size: NSSize(width: 1728, height: 1050)
    )
    try light.write(to: output.appendingPathComponent("工作区-浅色.png"), options: .atomic)
    try dark.write(to: output.appendingPathComponent("工作区-深色.png"), options: .atomic)
    try compact.write(to: output.appendingPathComponent("工作区-紧凑1024x700.png"), options: .atomic)
    try wide.write(to: output.appendingPathComponent("工作区-宽屏1728x1050.png"), options: .atomic)

    #expect(light.count > 50_000)
    #expect(dark.count > 50_000)
    #expect(compact.count > 35_000)
    #expect(wide.count > 60_000)
    #expect(light != dark)
}

@MainActor
@Test func realSourceEditorDrawsVisibleGlyphs() throws {
    guard let projectPath = ProcessInfo.processInfo.environment["SOURCELEAF_REAL_PROJECT"],
          let outputPath = ProcessInfo.processInfo.environment["SOURCELEAF_SNAPSHOT_OUTPUT"] else { return }
    let output = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let defaults = try #require(UserDefaults(suiteName: "SourceLeaf.source-visibility.\(UUID().uuidString)"))
    let model = AppModel(
        restoreLastProject: false,
        supportDirectory: output.appendingPathComponent("源码可见性状态", isDirectory: true),
        defaults: defaults
    )
    model.openProject(URL(fileURLWithPath: projectPath, isDirectory: true))
    #expect(model.sourceText.count > 10_000)

    let hostingView = NSHostingView(
        rootView: SourceTextView(
            text: Binding(get: { model.sourceText }, set: { _ in }),
            selection: .constant(NSRange(location: 0, length: 0)),
            showSelectionButton: false,
            onAskAI: {}
        )
        .frame(width: 820, height: 780)
    )
    hostingView.frame = NSRect(x: 0, y: 0, width: 820, height: 780)
    hostingView.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))

    let textView = try #require(findSourceTextView(in: hostingView))
    let visibleRect = textView.visibleRect
    let representation = try #require(textView.bitmapImageRepForCachingDisplay(in: visibleRect))
    textView.cacheDisplay(in: visibleRect, to: representation)
    let data = try #require(representation.representation(using: .png, properties: [:]))
    try data.write(to: output.appendingPathComponent("源码编辑器-局部.png"), options: .atomic)
    #expect(visibleInkPixelCount(in: representation) > 1_000)
}

@MainActor
@Test func dockHostedSourceEditorHasAVisibleDocumentView() throws {
    guard let projectPath = ProcessInfo.processInfo.environment["SOURCELEAF_REAL_PROJECT"] else { return }
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("SourceLeaf-dock-editor-\(UUID().uuidString)", isDirectory: true)
    let defaults = try #require(UserDefaults(suiteName: "SourceLeaf.dock-editor.\(UUID().uuidString)"))
    let model = AppModel(restoreLastProject: false, supportDirectory: support, defaults: defaults)
    model.openProject(URL(fileURLWithPath: projectPath, isDirectory: true))
    let hostingView = NSHostingView(
        rootView: WorkspaceView()
            .environmentObject(model)
            .frame(width: 1440, height: 900)
    )
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
        styleMask: [.titled, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    defer {
        window.contentView = nil
        window.close()
    }
    hostingView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    hostingView.layoutSubtreeIfNeeded()
    window.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

    let textView = try #require(findSourceTextView(in: hostingView))
    let layoutManager = try #require(textView.layoutManager)
    let textContainer = try #require(textView.textContainer)
    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)
    #expect(textView.string == model.sourceText)
    #expect(textView.visibleRect.width > 250)
    #expect(textView.visibleRect.height > 300)
    #expect(textView.frame.height >= min(usedRect.maxY + 20, 500))
    #expect(usedRect.width > 100)
    let visible = textView.visibleRect
    let representation = try #require(textView.bitmapImageRepForCachingDisplay(in: visible))
    textView.cacheDisplay(in: visible, to: representation)
    #expect(visibleInkPixelCount(in: representation) > 1_000)
    if let outputPath = ProcessInfo.processInfo.environment["SOURCELEAF_SNAPSHOT_OUTPUT"],
       let data = representation.representation(using: .png, properties: [:]) {
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try data.write(to: output.appendingPathComponent("源码编辑器-Dock宿主.png"), options: .atomic)
    }
}

@MainActor
@Test func keyWindowCompositorActuallyContainsSourceGlyphs() throws {
    guard let projectPath = ProcessInfo.processInfo.environment["SOURCELEAF_REAL_PROJECT"] else { return }
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("SourceLeaf-key-window-editor-\(UUID().uuidString)", isDirectory: true)
    let defaults = try #require(UserDefaults(suiteName: "SourceLeaf.key-window-editor.\(UUID().uuidString)"))
    let model = AppModel(restoreLastProject: false, supportDirectory: support, defaults: defaults)
    model.openProject(URL(fileURLWithPath: projectPath, isDirectory: true))
    let hostingView = NSHostingView(rootView: WorkspaceView().environmentObject(model))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
        styleMask: [.titled, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    defer {
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }
    window.center()
    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    hostingView.layoutSubtreeIfNeeded()
    window.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))

    let textView = try #require(findSourceTextView(in: hostingView))
    window.makeFirstResponder(textView)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    let populated = try #require(captureWindow(window))
    let original = textView.string
    let blankSource = original.map { $0 == "\n" ? "\n" : " " }.reduce(into: "") { $0.append($1) }
    textView.insertText(
        blankSource,
        replacementRange: NSRange(location: 0, length: (original as NSString).length)
    )
    textView.layoutManager?.ensureLayout(for: try #require(textView.textContainer))
    textView.needsDisplay = true
    if let overlay = findGlyphOverlay(in: hostingView) {
        overlay.needsDisplay = true
        overlay.displayIfNeeded()
    }
    hostingView.needsDisplay = true
    hostingView.displayIfNeeded()
    window.displayIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    let blank = try #require(captureWindow(window))

    let editorInWindow = textView.convert(textView.visibleRect, to: nil)
    let scaleX = CGFloat(populated.pixelsWide) / window.frame.width
    let scaleY = CGFloat(populated.pixelsHigh) / window.frame.height
    let sourcePixels = NSRect(
        x: (editorInWindow.minX + 60) * scaleX,
        y: (editorInWindow.minY + 8) * scaleY,
        width: max(1, (editorInWindow.width - 80) * scaleX),
        height: max(1, (editorInWindow.height - 16) * scaleY)
    )
    let changedPixels = sampledPixelDifference(populated, blank, in: sourcePixels)
    #expect(changedPixels > 300)

    if let outputPath = ProcessInfo.processInfo.environment["SOURCELEAF_SNAPSHOT_OUTPUT"] {
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if let data = populated.representation(using: .png, properties: [:]) {
            try data.write(to: output.appendingPathComponent("源码编辑器-真实窗口合成.png"), options: .atomic)
        }
        if let data = blank.representation(using: .png, properties: [:]) {
            try data.write(to: output.appendingPathComponent("源码编辑器-真实窗口空格对照.png"), options: .atomic)
        }
    }
}

@MainActor
@Test func latexToolbarCommandUsesNativeTextEditingAndUndo() async throws {
    let state = SourceEditorHarnessState()
    state.commandRequest = LaTeXEditRequest(command: .bold)
    let hostingView = NSHostingView(rootView: SourceEditorHarnessView(state: state))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    defer {
        window.contentView = nil
        window.close()
    }
    window.makeKeyAndOrderFront(nil)
    hostingView.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    let textView = try #require(findSourceTextView(in: hostingView))
    window.makeFirstResponder(textView)
    #expect(textView.window === window)
    try await Task.sleep(for: .milliseconds(600))

    #expect(state.text == "\\textbf{alpha}")
    #expect(state.selection == NSRange(location: 8, length: 5))
    #expect(textView.undoManager?.canUndo == true)

    textView.undoManager?.undo()
    try await Task.sleep(for: .milliseconds(50))
    #expect(state.text == "alpha")
}

@MainActor
@Test func projectTreeAndOutlineUseAResizableVerticalSplit() throws {
    guard let projectPath = ProcessInfo.processInfo.environment["SOURCELEAF_REAL_PROJECT"] else { return }
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("SourceLeaf-project-split-\(UUID().uuidString)", isDirectory: true)
    let defaults = try #require(UserDefaults(suiteName: "SourceLeaf.project-split.\(UUID().uuidString)"))
    let model = AppModel(restoreLastProject: false, supportDirectory: support, defaults: defaults)
    model.openProject(URL(fileURLWithPath: projectPath, isDirectory: true))

    let hostingView = NSHostingView(rootView: ProjectPanel().environmentObject(model))
    hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 760)
    hostingView.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

    let splitViews = findSplitViews(in: hostingView)
    #expect(splitViews.contains { !$0.isVertical && $0.subviews.count >= 2 })
    model.toggleProjectOutline()
    #expect(!model.projectOutlineExpanded)
}

@MainActor
@Test func sourceTabRemainsVisibleAfterImageSwitchesAndPanelResizing() throws {
    guard let projectPath = ProcessInfo.processInfo.environment["SOURCELEAF_REAL_PROJECT"] else { return }
    let project = URL(fileURLWithPath: projectPath, isDirectory: true)
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("SourceLeaf-editor-switch-\(UUID().uuidString)", isDirectory: true)
    let defaults = try #require(UserDefaults(suiteName: "SourceLeaf.editor-switch.\(UUID().uuidString)"))
    let model = AppModel(restoreLastProject: false, supportDirectory: support, defaults: defaults)
    model.openProject(project)
    let source = try #require(model.selectedFile)
    let expectedSource = try String(contentsOf: source.url, encoding: .utf8)
    let image = try #require(model.projectFiles.first {
        $0.kind == .image && ["png", "jpg", "jpeg", "svg"].contains($0.url.pathExtension.lowercased())
    })
    model.openFile(image)

    let hostingView = NSHostingView(rootView: WorkspaceView().environmentObject(model))
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

    for width in [1180.0, 760.0, 1360.0, 900.0] {
        model.selectPanel(.source, in: .center)
        window.setContentSize(NSSize(width: width, height: 760))
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.12))

        let textView = try #require(findSourceTextView(in: hostingView))
        #expect(textView.string == model.sourceText)
        #expect(textView.string == expectedSource)
        #expect(textView.visibleRect.width > 200)
        #expect(textView.visibleRect.height > 250)
        let visible = textView.visibleRect
        let representation = try #require(textView.bitmapImageRepForCachingDisplay(in: visible))
        textView.cacheDisplay(in: visible, to: representation)
        #expect(visibleInkPixelCount(in: representation) > 500)

        model.selectPanel(.image, in: .center)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        #expect(model.layout.selected[.center] == .image)
    }
}

@MainActor
@Test func codexReviewPanelRendersARealSelectionAndDiff() throws {
    guard let projectPath = ProcessInfo.processInfo.environment["SOURCELEAF_REAL_PROJECT"],
          let outputPath = ProcessInfo.processInfo.environment["SOURCELEAF_SNAPSHOT_OUTPUT"] else { return }
    let output = URL(fileURLWithPath: outputPath, isDirectory: true)
    let defaults = try #require(UserDefaults(suiteName: "SourceLeaf.codex-snapshot.\(UUID().uuidString)"))
    let standardLanguage = UserDefaults.standard.object(forKey: L10n.languageDefaultsKey)
    UserDefaults.standard.set(AppLanguage.simplifiedChinese.rawValue, forKey: L10n.languageDefaultsKey)
    defer {
        if let standardLanguage { UserDefaults.standard.set(standardLanguage, forKey: L10n.languageDefaultsKey) }
        else { UserDefaults.standard.removeObject(forKey: L10n.languageDefaultsKey) }
    }
    let model = AppModel(
        restoreLastProject: false,
        supportDirectory: output.appendingPathComponent("Codex快照状态", isDirectory: true),
        defaults: defaults
    )
    model.openProject(URL(fileURLWithPath: projectPath, isDirectory: true))
    let source = model.sourceText as NSString
    let phrase = "Hoist with His Own Petard"
    let phraseRange = source.range(of: phrase)
    model.selectedRange = phraseRange.location == NSNotFound
        ? NSRange(location: 0, length: min(40, source.length))
        : phraseRange
    model.attachCurrentSelection()
    let target = try #require(model.editTargets.first)
    let replacement = ProposedReplacement(
        targetID: target.id,
        replacement: "Hoist by Its Own Petard",
        explanation: "Tightens the title phrase while preserving its intended meaning."
    )
    model.messages = [
        ChatMessage(role: .user, text: "请在不改变事实含义的前提下，让标题更简洁。"),
        ChatMessage(role: .assistant, text: "已生成一项受选区约束的修改建议，请审阅差异。")
    ]
    model.pendingProposal = AIProposal(
        summary: "One title phrase was tightened.",
        replacements: [replacement],
        providerName: "Local Codex"
    )
    model.proposalValidation = [replacement.id: LaTeXValidator.validate(
        original: target.originalText,
        replacement: replacement.replacement
    )]

    let light = try render(
        CodexPanel()
            .environmentObject(model)
            .environment(\.colorScheme, .light),
        size: NSSize(width: 620, height: 820)
    )
    let dark = try render(
        CodexPanel()
            .environmentObject(model)
            .environment(\.colorScheme, .dark),
        size: NSSize(width: 620, height: 820)
    )
    try light.write(to: output.appendingPathComponent("Codex审阅-浅色.png"), options: .atomic)
    try dark.write(to: output.appendingPathComponent("Codex审阅-深色.png"), options: .atomic)
    #expect(light.count > 45_000)
    #expect(dark.count > 45_000)
    #expect(light != dark)
}

@MainActor
private func render<V: View>(_ view: V, size: NSSize) throws -> Data {
    let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    hostingView.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
        contentRect: hostingView.frame,
        styleMask: [.titled, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    defer {
        window.contentView = nil
        window.close()
    }
    hostingView.layoutSubtreeIfNeeded()
    window.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

    let representation = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
    hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
    return try #require(representation.representation(using: .png, properties: [:]))
}


@MainActor
private func findTextView(in view: NSView) -> NSTextView? {
    if let textView = view as? NSTextView { return textView }
    for child in view.subviews {
        if let result = findTextView(in: child) { return result }
    }
    return nil
}

@MainActor
private func findSourceTextView(in view: NSView) -> NSTextView? {
    if let textView = view as? NSTextView,
       textView.enclosingScrollView?.verticalRulerView is LineNumberRulerView {
        return textView
    }
    for child in view.subviews {
        if let result = findSourceTextView(in: child) { return result }
    }
    return nil
}

@MainActor
private func findGlyphOverlay(in view: NSView) -> SourceGlyphOverlayView? {
    if let overlay = view as? SourceGlyphOverlayView { return overlay }
    for child in view.subviews {
        if let result = findGlyphOverlay(in: child) { return result }
    }
    return nil
}

@MainActor
private final class SourceEditorHarnessState: ObservableObject {
    @Published var text = "alpha"
    @Published var selection = NSRange(location: 0, length: 5)
    @Published var commandRequest: LaTeXEditRequest?
}

@MainActor
private struct SourceEditorHarnessView: View {
    @ObservedObject var state: SourceEditorHarnessState

    var body: some View {
        SourceTextView(
            text: $state.text,
            selection: $state.selection,
            commandRequest: state.commandRequest,
            showSelectionButton: false,
            onAskAI: {},
            onCommandApplied: { id in
                if state.commandRequest?.id == id { state.commandRequest = nil }
            }
        )
        .frame(width: 640, height: 420)
    }
}

@MainActor
private func findPDFView(in view: NSView) -> PDFView? {
    if let pdfView = view as? PDFView { return pdfView }
    for child in view.subviews {
        if let result = findPDFView(in: child) { return result }
    }
    return nil
}

@MainActor
private func findSplitViews(in view: NSView) -> [NSSplitView] {
    var result = view is NSSplitView ? [view as! NSSplitView] : []
    for child in view.subviews {
        result.append(contentsOf: findSplitViews(in: child))
    }
    return result
}

private func visibleInkPixelCount(in bitmap: NSBitmapImageRep) -> Int {
    guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
          let background = bitmap.colorAt(x: bitmap.pixelsWide - 1, y: bitmap.pixelsHigh - 1)?.usingColorSpace(.deviceRGB) else {
        return 0
    }
    var count = 0
    for y in stride(from: 2, to: bitmap.pixelsHigh - 2, by: 3) {
        for x in stride(from: 2, to: bitmap.pixelsWide - 2, by: 3) {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let delta = abs(color.redComponent - background.redComponent)
                + abs(color.greenComponent - background.greenComponent)
                + abs(color.blueComponent - background.blueComponent)
            if delta > 0.18 { count += 1 }
        }
    }
    return count
}

@MainActor
private func captureWindow(_ window: NSWindow) -> NSBitmapImageRep? {
    guard let image = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(window.windowNumber),
        [.boundsIgnoreFraming, .bestResolution]
    ) else { return nil }
    return NSBitmapImageRep(cgImage: image)
}

private func sampledPixelDifference(
    _ lhs: NSBitmapImageRep,
    _ rhs: NSBitmapImageRep,
    in rect: NSRect? = nil
) -> Int {
    guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return 0 }
    let bounds = NSRect(x: 0, y: 0, width: lhs.pixelsWide, height: lhs.pixelsHigh)
    let sampleRect = (rect ?? bounds).intersection(bounds).integral
    var changed = 0
    for y in stride(from: max(2, Int(sampleRect.minY)), to: min(lhs.pixelsHigh - 2, Int(sampleRect.maxY)), by: 2) {
        for x in stride(from: max(2, Int(sampleRect.minX)), to: min(lhs.pixelsWide - 2, Int(sampleRect.maxX)), by: 2) {
            guard let left = lhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  let right = rhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let delta = abs(left.redComponent - right.redComponent)
                + abs(left.greenComponent - right.greenComponent)
                + abs(left.blueComponent - right.blueComponent)
            if delta > 0.12 { changed += 1 }
        }
    }
    return changed
}
