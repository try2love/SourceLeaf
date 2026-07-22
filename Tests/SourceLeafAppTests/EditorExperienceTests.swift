import AppKit
import SwiftUI
import Testing
@testable import SourceLeafApp

@MainActor
@Test func overleafStyleSyntaxKeepsCommentsUnifiedAndOptionalArgumentsDistinct() async throws {
    let source = "% \\section{commented}\n\\documentclass[lettersize,journal]{IEEEtran}\n$E=mc^2$"
    let host = makeEditorHost(source: source, theme: .light, fontFamily: "Menlo", fontSize: 15)
    defer { closeEditorHost(host) }
    try await Task.sleep(for: .milliseconds(400))
    let textView = try #require(findSourceTextView(in: host.view))
    let coordinator = try #require(textView.delegate as? SourceTextView.Coordinator)
    coordinator.applyHighlighting()
    let storage = try #require(textView.textStorage)
    let nsSource = source as NSString

    let commentStart = nsSource.range(of: "%").location
    let commentedCommand = nsSource.range(of: "\\section").location
    let command = nsSource.range(of: "\\documentclass").location
    let optional = nsSource.range(of: "lettersize").location
    let body = nsSource.range(of: "IEEEtran").location
    let math = nsSource.range(of: "E=mc^2").location

    let commentColor = try foregroundColor(storage, at: commentStart)
    #expect(colorsMatch(commentColor, try foregroundColor(storage, at: commentedCommand)))
    #expect(!colorsMatch(commentColor, try foregroundColor(storage, at: command)))
    #expect(!colorsMatch(try foregroundColor(storage, at: optional), try foregroundColor(storage, at: body)))
    #expect(!colorsMatch(try foregroundColor(storage, at: math), try foregroundColor(storage, at: body)))
    #expect(textView.font?.pointSize == 15)
}

@MainActor
@Test func editorSelectionCaretAndHorizontalGeometryRemainReadable() async throws {
    let source = "\\section{A very long heading that should wrap instead of moving beneath the line number gutter}"
    let host = makeEditorHost(source: source, theme: .light, fontFamily: "Menlo", fontSize: 16)
    defer { closeEditorHost(host) }
    try await Task.sleep(for: .milliseconds(400))
    let textView = try #require(findSourceTextView(in: host.view))
    let scrollView = try #require(textView.enclosingScrollView)
    let ruler = try #require(scrollView.verticalRulerView as? LineNumberRulerView)
    let overlay = try #require(findGlyphOverlay(in: host.view))

    let background = try #require(textView.selectedTextAttributes[.backgroundColor] as? NSColor)
    let foreground = try #require(textView.selectedTextAttributes[.foregroundColor] as? NSColor)
    #expect(!colorsMatch(background, foreground))
    #expect(!colorsMatch(foreground, .white))
    #expect(!colorsMatch(textView.insertionPointColor, textView.backgroundColor))
    #expect(!scrollView.hasHorizontalScroller)
    #expect(scrollView.horizontalScrollElasticity == .none)
    #expect(!textView.isHorizontallyResizable)
    #expect(textView.textContainer?.widthTracksTextView == true)
    let textOrigin = textView.convert(textView.textContainerOrigin, to: scrollView)
    let rulerRightEdge = ruler.convert(ruler.bounds, to: scrollView).maxX
    #expect(textOrigin.x >= rulerRightEdge + 6)

    textView.setSelectedRange(NSRange(location: 10, length: 18))
    host.window.makeFirstResponder(textView)
    overlay.needsDisplay = true
    overlay.displayIfNeeded()
    #expect(overlay.lastSelectionRectCount > 0)

    textView.setSelectedRange(NSRange(location: 12, length: 0))
    overlay.needsDisplay = true
    overlay.displayIfNeeded()
    #expect(overlay.lastCaretRect != nil)

    scrollView.contentView.scroll(to: NSPoint(x: 80, y: 0))
    NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    await Task.yield()
    #expect(abs(scrollView.contentView.bounds.origin.x) < 0.5)
}

@MainActor
@Test func largeDocumentSelectionUpdatesStayWithinInteractiveBudget() async throws {
    let source = Array(
        repeating: "\\section{Selection performance} Long LaTeX source with \\cite{reference} and $E=mc^2$.",
        count: 6_000
    ).joined(separator: "\n")
    let state = SelectionPerformanceState(source: source)
    let view = NSHostingView(rootView: SelectionPerformanceHarness(state: state))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentView = view
    window.makeKeyAndOrderFront(nil)
    defer {
        window.contentView = nil
        window.close()
    }
    try await Task.sleep(for: .milliseconds(650))
    let textView = try #require(findSourceTextView(in: view))
    window.makeFirstResponder(textView)

    let clock = ContinuousClock()
    let started = clock.now
    for step in 0..<80 {
        textView.setSelectedRange(NSRange(location: step * 53, length: 31))
        await Task.yield()
    }
    let elapsed = started.duration(to: clock.now)

    #expect(elapsed < .seconds(1), "80 selection updates took \(elapsed)")
}

@MainActor
@Test func selectionOverlayPaintsEveryDragStepSynchronously() async throws {
    let host = makeEditorHost(source: String(repeating: "live selection ", count: 200), theme: .light, fontFamily: "Menlo", fontSize: 14)
    defer { closeEditorHost(host) }
    try await Task.sleep(for: .milliseconds(400))
    let textView = try #require(findSourceTextView(in: host.view))
    let overlay = try #require(findGlyphOverlay(in: host.view))
    host.window.makeFirstResponder(textView)

    textView.setSelectedRange(NSRange(location: 0, length: 8))
    #expect(overlay.lastPaintedSelection == NSRange(location: 0, length: 8))
    textView.setSelectedRange(NSRange(location: 0, length: 24))
    #expect(overlay.lastPaintedSelection == NSRange(location: 0, length: 24))
}

@MainActor
@Test func sourceCaretBlinksWhileTheEditorIsFocused() async throws {
    let host = makeEditorHost(source: "\\section{Blinking caret}", theme: .light, fontFamily: "Menlo", fontSize: 16)
    defer { closeEditorHost(host) }
    try await Task.sleep(for: .milliseconds(400))
    let textView = try #require(findSourceTextView(in: host.view))
    let overlay = try #require(findGlyphOverlay(in: host.view))
    host.window.makeFirstResponder(textView)
    textView.setSelectedRange(NSRange(location: 4, length: 0))
    overlay.needsDisplay = true
    overlay.displayIfNeeded()
    #expect(overlay.lastCaretRect != nil)
    #expect(overlay.caretBlinkAnimationActive)

    try await Task.sleep(for: .milliseconds(650))
    #expect(overlay.caretBlinkAnimationActive)
}

@MainActor
@Test func editorThemesRenderSyntaxSelectionAndCaretSnapshots() async throws {
    guard let outputPath = ProcessInfo.processInfo.environment["SOURCELEAF_EDITOR_SNAPSHOT_OUTPUT"] else { return }
    let output = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let state = EditorSnapshotState()
    let view = NSHostingView(rootView: EditorSnapshotHarness(state: state))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
        styleMask: [.titled, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentView = view
    window.makeKeyAndOrderFront(nil)
    defer {
        window.contentView = nil
        window.close()
    }

    try await Task.sleep(for: .milliseconds(500))
    let lightTextView = try #require(findSourceTextView(in: view))
    window.makeFirstResponder(lightTextView)
    lightTextView.setSelectedRange(state.selection)
    findGlyphOverlay(in: view)?.needsDisplay = true
    window.displayIfNeeded()
    let light = try #require(captureEditorWindow(window)?.representation(using: .png, properties: [:]))
    try light.write(to: output.appendingPathComponent("编辑器-Overleaf浅色选区.png"), options: .atomic)

    state.theme = .dark
    state.selection = NSRange(location: 16, length: 0)
    try await Task.sleep(for: .milliseconds(350))
    let darkTextView = try #require(findSourceTextView(in: view))
    window.makeFirstResponder(darkTextView)
    darkTextView.setSelectedRange(state.selection)
    findGlyphOverlay(in: view)?.needsDisplay = true
    window.displayIfNeeded()
    let dark = try #require(captureEditorWindow(window)?.representation(using: .png, properties: [:]))
    try dark.write(to: output.appendingPathComponent("编辑器-深色光标.png"), options: .atomic)

    #expect(light.count > 35_000)
    #expect(dark.count > 35_000)
    #expect(light != dark)
}

@MainActor
private final class EditorSnapshotState: ObservableObject {
    @Published var theme: EditorTheme = .light
    @Published var selection = NSRange(location: 56, length: 18)
    let source = """
    \\documentclass[lettersize,journal]{IEEEtran}
    \\usepackage[caption=false,font=normalsize]{subfig}
    % Updated with editorial comments
    \\begin{document}
    \\section{Introduction}
    Selected source remains readable while highlighted.
    $E = mc^2$ and \\cite{example}.
    \\subsection{Method}
    The editor wraps long LaTeX lines instead of scrolling beneath the line-number gutter.
    \\end{document}
    """
}

@MainActor
private final class SelectionPerformanceState: ObservableObject {
    let source: String
    @Published var selection = NSRange(location: 0, length: 0)

    init(source: String) { self.source = source }
}

@MainActor
private struct SelectionPerformanceHarness: View {
    @ObservedObject var state: SelectionPerformanceState

    var body: some View {
        SourceTextView(
            text: .constant(state.source),
            selection: $state.selection,
            showSelectionButton: false,
            editorTheme: .light,
            editorFontFamily: "Menlo",
            editorFontSize: 14,
            onAskAI: {}
        )
    }
}

@MainActor
private struct EditorSnapshotHarness: View {
    @ObservedObject var state: EditorSnapshotState

    var body: some View {
        SourceTextView(
            text: .constant(state.source),
            selection: $state.selection,
            showSelectionButton: false,
            editorTheme: state.theme,
            editorFontFamily: "Menlo",
            editorFontSize: 16,
            onAskAI: {}
        )
        .preferredColorScheme(state.theme.colorScheme)
    }
}

@MainActor
private func makeEditorHost(
    source: String,
    theme: EditorTheme,
    fontFamily: String,
    fontSize: Double
) -> (window: NSWindow, view: NSHostingView<SourceTextView>) {
    let editor = SourceTextView(
        text: .constant(source),
        selection: .constant(NSRange(location: 0, length: 0)),
        showSelectionButton: false,
        editorTheme: theme,
        editorFontFamily: fontFamily,
        editorFontSize: fontSize,
        onAskAI: {}
    )
    let view = NSHostingView(rootView: editor)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    window.makeKeyAndOrderFront(nil)
    view.layoutSubtreeIfNeeded()
    return (window, view)
}

@MainActor
private func closeEditorHost(_ host: (window: NSWindow, view: NSHostingView<SourceTextView>)) {
    host.window.contentView = nil
    host.window.close()
}

@MainActor
private func findSourceTextView(in view: NSView) -> NSTextView? {
    if let textView = view as? NSTextView,
       textView.enclosingScrollView?.verticalRulerView is LineNumberRulerView {
        return textView
    }
    for child in view.subviews {
        if let match = findSourceTextView(in: child) { return match }
    }
    return nil
}

@MainActor
private func findGlyphOverlay(in view: NSView) -> SourceGlyphOverlayView? {
    if let overlay = view as? SourceGlyphOverlayView { return overlay }
    for child in view.subviews {
        if let match = findGlyphOverlay(in: child) { return match }
    }
    return nil
}

private func foregroundColor(_ storage: NSTextStorage, at location: Int) throws -> NSColor {
    try #require(storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor)
}

private func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
    guard let left = lhs.usingColorSpace(.deviceRGB), let right = rhs.usingColorSpace(.deviceRGB) else { return false }
    return abs(left.redComponent - right.redComponent) < 0.01
        && abs(left.greenComponent - right.greenComponent) < 0.01
        && abs(left.blueComponent - right.blueComponent) < 0.01
        && abs(left.alphaComponent - right.alphaComponent) < 0.01
}

@MainActor
private func captureEditorWindow(_ window: NSWindow) -> NSBitmapImageRep? {
    guard let image = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(window.windowNumber),
        [.boundsIgnoreFraming, .bestResolution]
    ) else { return nil }
    return NSBitmapImageRep(cgImage: image)
}
