import AppKit
import SourceLeafCore
import SwiftUI
import Testing
@testable import SourceLeafApp

@Test func staleSwiftUIEchoNeverOverwritesNewerNativeTyping() {
    #expect(!SourceTextSynchronization.shouldApplyExternalText(
        incoming: "t",
        nativeText: "te",
        lastLocallyEmittedText: "te"
    ))
    #expect(SourceTextSynchronization.shouldApplyExternalText(
        incoming: "accepted external replacement",
        nativeText: "local source",
        lastLocallyEmittedText: nil
    ))
}

@MainActor
@Test func composerReturnDoesNotSendWhileInputMethodHasMarkedText() {
    #expect(!ComposerNSTextView.shouldTreatReturnAsSend(
        characters: "\r",
        modifierFlags: [],
        sendBehavior: .enter,
        hasMarkedText: true
    ))
    #expect(!ComposerNSTextView.shouldTreatReturnAsSend(
        characters: "\r",
        modifierFlags: [],
        sendBehavior: .enter,
        hasMarkedText: false,
        recentlyCommittedMarkedText: true
    ))
    #expect(!ComposerNSTextView.shouldTreatReturnAsSend(
        characters: "\r",
        modifierFlags: [],
        sendBehavior: .enter,
        hasMarkedText: false,
        compositionInputSourceActive: true
    ))
    #expect(!ComposerNSTextView.shouldTreatReturnAsSend(
        characters: "\r",
        modifierFlags: [],
        sendBehavior: .enter,
        hasMarkedText: false,
        recentlyTypedWithCompositionInputSource: true
    ))
    #expect(ComposerNSTextView.shouldTreatReturnAsSend(
        characters: "\r",
        modifierFlags: [],
        sendBehavior: .enter,
        hasMarkedText: false
    ))
    #expect(!ComposerNSTextView.shouldTreatReturnAsSend(
        characters: "\r",
        modifierFlags: [],
        sendBehavior: .shiftEnter,
        hasMarkedText: false
    ))
    #expect(ComposerNSTextView.shouldTreatReturnAsSend(
        characters: "\r",
        modifierFlags: [.shift],
        sendBehavior: .shiftEnter,
        hasMarkedText: false
    ))
}

@MainActor
@Test func composerRecognizesCommonCJKInputSourcesAsReturnCommitSources() {
    #expect(ComposerNSTextView.inputSourcePrefersReturnCommit(
        sourceID: "com.apple.inputmethod.SCIM.ITABC",
        localizedName: "简体拼音",
        languages: ["zh-Hans"]
    ))
    #expect(ComposerNSTextView.inputSourcePrefersReturnCommit(
        sourceID: "com.apple.keylayout.ABC",
        localizedName: "ABC",
        languages: ["en"]
    ) == false)
    #expect(ComposerNSTextView.inputSourcePrefersReturnCommit(
        sourceID: "com.sogou.inputmethod.sogou.pinyin",
        localizedName: "搜狗拼音",
        languages: ["zh-Hans"]
    ))
    #expect(ComposerNSTextView.inputSourcePrefersReturnCommit(
        sourceID: "im.rime.inputmethod.Squirrel",
        localizedName: "鼠须管",
        languages: ["zh-Hans"]
    ))
}

@MainActor
@Test func shortChatBubbleWidthTracksTheMessageInsteadOfUsingTheMaximum() {
    #expect(ChatBubble.preferredBubbleWidth(for: "python") < 100)
    #expect(ChatBubble.preferredBubbleWidth(for: "最简单直观的方式介绍你自己") < 360)
    #expect(ChatBubble.preferredBubbleWidth(for: String(repeating: "long markdown reply ", count: 80)) == ChatBubble.maximumBubbleWidth)
}

@Test func chatMarkdownRecognizesTablesAsStructuredBlocks() {
    let blocks = ChatMarkdownBlock.parse("""
    | 功能 | 状态 |
    | --- | --- |
    | Markdown | 已支持 |
    """)

    guard case let .table(rows) = blocks.first?.kind else {
        Issue.record("Expected a Markdown table block")
        return
    }
    #expect(rows == [["功能", "状态"], ["Markdown", "已支持"]])
}

@Test func sourceFindMatchesAllOccurrencesForPersistentHighlighting() {
    let matches = SourceFindController.matches(in: "alpha beta Alpha alphabet", query: "alpha")

    #expect(matches.count == 3)
    #expect(matches.map(\.location) == [0, 11, 17])
}

@MainActor
@Test func sourceFindOverlayPaintsInactiveMatchesAlongsideTheActiveMatch() async throws {
    let host = makeEditorHost(source: "alpha beta Alpha alphabet", theme: .light, fontFamily: "Menlo", fontSize: 15)
    defer { closeEditorHost(host) }
    try await Task.sleep(for: .milliseconds(400))
    let overlay = try #require(findGlyphOverlay(in: host.view))
    let matches = SourceFindController.matches(in: "alpha beta Alpha alphabet", query: "alpha")

    overlay.findRanges = matches
    overlay.activeFindRange = matches.first
    overlay.needsDisplay = true
    overlay.displayIfNeeded()

    #expect(overlay.lastFindHighlightRectCount >= matches.count)
}

@Test func latexCompletionOffersCoreCommandsAfterBackslash() {
    let suggestions = LaTeXCompletionEngine.suggestions(prefix: "\\", source: "\\documentclass{article}")
    let insertions = suggestions.map(\.insertion)

    #expect(insertions.contains("\\usepackage{}"))
    #expect(insertions.contains("\\begin{}"))
    #expect(insertions.contains("\\item"))
    #expect(insertions.contains("\\includegraphics[]{}"))
}

@Test func latexCompletionNarrowsByCommandPrefixAndTracksReplacementRange() throws {
    let source = "\\us" as NSString
    let command = try #require(LaTeXCompletionEngine.commandPrefix(in: source, cursorLocation: source.length))
    let suggestions = LaTeXCompletionEngine.suggestions(prefix: command.prefix, source: source as String)

    #expect(command.prefix == "\\us")
    #expect(command.range == NSRange(location: 0, length: 3))
    #expect(suggestions.map(\.insertion).contains("\\usepackage{}"))
    #expect(!suggestions.map(\.insertion).contains("\\begin{}"))
}

@Test func latexCompletionSuggestsCitationsLabelsAndGraphicsInArguments() throws {
    let context = LaTeXCompletionContext(
        index: ProjectIndex(
            rootDocument: "main.tex",
            sectionSummaries: [:],
            labels: ["sec:method": "main.tex", "fig:overview": "main.tex"],
            citations: ["smith2024rag", "zhang2025attack"],
            includedFiles: ["figures/overview.png", "figures/results.pdf"]
        ),
        projectFiles: ["sections/method.tex", "references.bib"]
    )

    let citeSource = "\\cite{smi" as NSString
    let citeContext = try #require(LaTeXCompletionEngine.argumentContext(in: citeSource, cursorLocation: citeSource.length))
    #expect(citeContext.command == "cite")
    #expect(citeContext.prefix == "smi")
    #expect(LaTeXCompletionEngine.argumentSuggestions(command: citeContext.command, prefix: citeContext.prefix, context: context).map(\.insertion) == ["smith2024rag"])

    let refSource = "\\ref{fig:" as NSString
    let refContext = try #require(LaTeXCompletionEngine.argumentContext(in: refSource, cursorLocation: refSource.length))
    #expect(LaTeXCompletionEngine.argumentSuggestions(command: refContext.command, prefix: refContext.prefix, context: context).map(\.insertion) == ["fig:overview"])

    let graphicSource = "\\includegraphics{figures/" as NSString
    let graphicContext = try #require(LaTeXCompletionEngine.argumentContext(in: graphicSource, cursorLocation: graphicSource.length))
    #expect(LaTeXCompletionEngine.argumentSuggestions(command: graphicContext.command, prefix: graphicContext.prefix, context: context).map(\.insertion) == ["figures/overview.png", "figures/results.pdf"])
}

@MainActor
@Test func rapidNativeTypingPreservesCharacterOrderAndCaretPosition() async throws {
    let state = TypingState()
    let view = NSHostingView(rootView: TypingHarness(state: state))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.makeKeyAndOrderFront(nil)
    defer { window.contentView = nil; window.close() }
    try await Task.sleep(for: .milliseconds(350))
    let textView = try #require(findSourceTextView(in: view))
    window.makeFirstResponder(textView)

    for (character, keyCode) in [("t", 17), ("e", 14), ("s", 1), ("t", 17)] {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ))
        textView.keyDown(with: event)
        await Task.yield()
    }
    try await Task.sleep(for: .milliseconds(160))
    #expect(textView.string == "test")
    #expect(state.text == "test")
    #expect(textView.selectedRange() == NSRange(location: 4, length: 0))
}

@MainActor
@Test func rapidMidLineTypingAndDeletionKeepTheNativeCaretMovingForward() async throws {
    let state = TypingState(text: "alpha omega", selection: NSRange(location: 6, length: 0))
    let view = NSHostingView(rootView: TypingHarness(state: state))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.makeKeyAndOrderFront(nil)
    defer { window.contentView = nil; window.close() }
    try await Task.sleep(for: .milliseconds(350))
    let textView = try #require(findSourceTextView(in: view))
    window.makeFirstResponder(textView)
    textView.setSelectedRange(NSRange(location: 6, length: 0))

    for (character, keyCode) in [("t", 17), ("e", 14), ("s", 1), ("t", 17)] {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ))
        textView.keyDown(with: event)
        try await Task.sleep(for: .milliseconds(15))
    }

    #expect(textView.string == "alpha testomega")
    #expect(textView.selectedRange() == NSRange(location: 10, length: 0))

    let delete = try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        characters: "\u{7f}",
        charactersIgnoringModifiers: "\u{7f}",
        isARepeat: false,
        keyCode: 51
    ))
    textView.keyDown(with: delete)
    try await Task.sleep(for: .milliseconds(80))

    #expect(textView.string == "alpha tesomega")
    #expect(textView.selectedRange() == NSRange(location: 9, length: 0))
    #expect(state.text == "alpha tesomega")
}

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
    let ruler = try #require(findLineNumberRuler(in: host.view))
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
    let coordinateView = try #require(ruler.superview)
    let textOrigin = textView.convert(textView.textContainerOrigin, to: coordinateView)
    let rulerRightEdge = ruler.convert(ruler.bounds, to: coordinateView).maxX
    #expect(textOrigin.x >= rulerRightEdge + 6)

    textView.setSelectedRange(NSRange(location: 10, length: 18))
    host.window.makeFirstResponder(textView)
    overlay.needsDisplay = true
    overlay.displayIfNeeded()
    #expect(textView.selectedRange() == NSRange(location: 10, length: 18))
    #expect(overlay.lastSelectionRectCount == 0)

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
    window.isReleasedWhenClosed = false
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
    window.isReleasedWhenClosed = false
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
private final class TypingState: ObservableObject {
    @Published var text: String
    @Published var selection: NSRange

    init(text: String = "", selection: NSRange = NSRange(location: 0, length: 0)) {
        self.text = text
        self.selection = selection
    }
}

@MainActor
private struct TypingHarness: View {
    @ObservedObject var state: TypingState

    var body: some View {
        SourceTextView(
            text: $state.text,
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
    window.isReleasedWhenClosed = false
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
       textView.delegate is SourceTextView.Coordinator {
        return textView
    }
    for child in view.subviews {
        if let match = findSourceTextView(in: child) { return match }
    }
    return nil
}

@MainActor
private func findLineNumberRuler(in view: NSView) -> LineNumberRulerView? {
    if let ruler = view as? LineNumberRulerView { return ruler }
    for child in view.subviews {
        if let match = findLineNumberRuler(in: child) { return match }
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
