import Foundation
import AppKit
import SourceLeafCore
import SwiftUI
@testable import SourceLeafApp
import XCTest

final class AppRegressionXCTests: XCTestCase {
    @MainActor
    func testComposerReturnDoesNotSendDuringInputMethodCommit() {
        XCTAssertFalse(ComposerNSTextView.shouldTreatReturnAsSend(
            characters: "\r",
            modifierFlags: [],
            sendBehavior: .enter,
            hasMarkedText: true
        ))
        XCTAssertFalse(ComposerNSTextView.shouldTreatReturnAsSend(
            characters: "\r",
            modifierFlags: [],
            sendBehavior: .enter,
            hasMarkedText: false,
            recentlyCommittedMarkedText: true
        ))
        XCTAssertTrue(ComposerNSTextView.shouldTreatReturnAsSend(
            characters: "\r",
            modifierFlags: [],
            sendBehavior: .enter,
            hasMarkedText: false
        ))
        XCTAssertFalse(ComposerNSTextView.shouldTreatReturnAsSend(
            characters: "\r",
            modifierFlags: [],
            sendBehavior: .enter,
            hasMarkedText: false,
            compositionInputSourceActive: true
        ))
        XCTAssertTrue(ComposerNSTextView.shouldTreatReturnAsSend(
            characters: "\r",
            modifierFlags: [.shift],
            sendBehavior: .shiftEnter,
            hasMarkedText: false,
            compositionInputSourceActive: true
        ))
    }

    func testFindMatchesReturnEveryOccurrenceForPersistentHighlighting() {
        let matches = SourceFindController.matches(in: "alpha beta Alpha alphabet", query: "alpha")

        XCTAssertEqual(matches.count, 3)
        XCTAssertEqual(matches.map(\.location), [0, 11, 17])
    }

    func testLatexCompletionCandidatesCoverCoreAuthoringCommands() {
        let suggestions = LaTeXCompletionEngine.suggestions(prefix: "\\", source: "\\documentclass{article}")
            .map(\.insertion)

        XCTAssertTrue(suggestions.contains("\\usepackage{}"))
        XCTAssertTrue(suggestions.contains("\\begin{}"))
        XCTAssertTrue(suggestions.contains("\\section{}"))
        XCTAssertTrue(suggestions.contains("\\includegraphics[]{}"))
        XCTAssertTrue(suggestions.contains("\\cite{}"))
    }

    func testLatexCompletionNarrowsCommandPrefixWithoutRepeatedAutoTriggering() {
        let source = "\\sec" as NSString
        XCTAssertFalse(LaTeXCompletionEngine.shouldTriggerCompletion(
            afterChangeIn: source,
            selection: NSRange(location: source.length, length: 0)
        ))
        let suggestions = LaTeXCompletionEngine.suggestions(prefix: "\\sec", source: source as String).map(\.insertion)
        XCTAssertTrue(suggestions.contains("\\section{}"))
        XCTAssertFalse(suggestions.contains("\\subsection{}"))
    }

    @MainActor
    func testSourceTypingKeepsCaretMovingForwardAfterBackslashCompletionTrigger() async throws {
        let state = SourceTypingState()
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)

        for (character, keyCode) in [
            ("\\", 42), ("s", 1), ("e", 14), ("c", 8), ("t", 17), ("i", 34), ("o", 31), ("n", 45)
        ] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: host.window)))
            try await Task.sleep(for: .milliseconds(18))
        }
        try await Task.sleep(for: .milliseconds(260))

        XCTAssertEqual(textView.string, "\\section")
        XCTAssertEqual(state.text, "\\section")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 8, length: 0))
    }

    @MainActor
    func testAcceptedLatexCompletionPlacesCaretInsideRequiredBraces() async throws {
        let state = SourceTypingState(text: "\\section{}", selection: NSRange(location: 8, length: 2))
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 8, length: 2))
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(textView.string, "\\section{}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 0))

        for (character, keyCode) in [("I", 34), ("n", 45), ("t", 17), ("r", 15), ("o", 31)] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: host.window)))
            try await Task.sleep(for: .milliseconds(12))
        }

        XCTAssertEqual(textView.string, "\\section{Intro}")
        XCTAssertEqual(state.text, "\\section{Intro}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 14, length: 0))
    }

    @MainActor
    func testRapidMidLineTypingAndDeleteKeepCaretAtTheNativeInsertionPoint() async throws {
        let state = SourceTypingState(text: "alpha omega", selection: NSRange(location: 6, length: 0))
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        for (character, keyCode) in [("t", 17), ("e", 14), ("s", 1), ("t", 17)] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: host.window)))
            try await Task.sleep(for: .milliseconds(12))
        }

        XCTAssertEqual(textView.string, "alpha testomega")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 10, length: 0))

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\u{7f}", keyCode: 51, window: host.window)))
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(textView.string, "alpha tesomega")
        XCTAssertEqual(state.text, "alpha tesomega")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 0))
    }

    @MainActor
    func testStaleSwiftUISelectionEchoCannotMoveCaretBackwardDuringRapidTyping() async throws {
        let state = SourceTypingState(text: "alpha omega", selection: NSRange(location: 6, length: 0))
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "t", keyCode: 17, window: host.window)))
        try await Task.sleep(for: .milliseconds(8))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 7, length: 0))

        // SwiftUI can deliver a stale selection binding from before the native
        // NSTextView edit has fully settled. The editor must not accept that
        // echo and move the caret backward, otherwise fast typing becomes
        // reordered, e.g. `test` can become `tset`.
        state.selection = NSRange(location: 6, length: 0)
        try await Task.sleep(for: .milliseconds(24))

        for (character, keyCode) in [("e", 14), ("s", 1), ("t", 17)] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: host.window)))
            try await Task.sleep(for: .milliseconds(8))
        }

        XCTAssertEqual(textView.string, "alpha testomega")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 10, length: 0))
    }

    @MainActor
    func testLatexSmartPairsInsertBracesAndSkipDuplicateClosers() async throws {
        let state = SourceTypingState(text: "\\section", selection: NSRange(location: 8, length: 0))
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 8, length: 0))

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "{", keyCode: 33, window: host.window)))
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(textView.string, "\\section{}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 0))

        for (character, keyCode) in [("I", 34), ("n", 45), ("t", 17), ("r", 15), ("o", 31)] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: host.window)))
            try await Task.sleep(for: .milliseconds(10))
        }
        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "}", keyCode: 30, window: host.window)))
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(textView.string, "\\section{Intro}")
        XCTAssertEqual(state.text, "\\section{Intro}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 15, length: 0))
    }

    func testRealMutedRAGProjectBuildsUsableFileAndCompletionIndexesWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["SOURCELEAF_REAL_PROJECT"] else { throw XCTSkip("SOURCELEAF_REAL_PROJECT not set") }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let files = ProjectIndexer.discoverFiles(root: root)
        let rootFile = try XCTUnwrap(files.first { $0.relativePath == "MutedRAG.tex" })
        let source = try String(contentsOf: rootFile.url, encoding: .utf8)
        let index = ProjectIndexer.completionIndex(files: files, activeFile: rootFile, activeSource: source)

        XCTAssertEqual(ProjectIndexer.detectRootDocument(files: files)?.relativePath, "MutedRAG.tex")
        XCTAssertTrue(files.contains { $0.relativePath == "reference.bib" && $0.kind == .bibliography })
        XCTAssertTrue(files.contains { $0.relativePath == "figures/overview.png" && $0.kind == .image })
        XCTAssertTrue(files.contains { $0.relativePath == "figures/author/PanSuo.jpg" && $0.kind == .image })
        XCTAssertFalse(index.citations.isEmpty)
        XCTAssertTrue(index.includedFiles.contains("figures/overview.png"))
    }

    @MainActor
    func testChatPanelDoesNotOverflowANarrowColumn() throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceLeaf-xctest-chat-width-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let project = support.appendingPathComponent("项目", isDirectory: true)
        let appSupport = support.appendingPathComponent("应用状态", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("\\documentclass{article}".utf8)
            .write(to: project.appendingPathComponent("main.tex"), options: .atomic)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SourceLeaf.xctest-chat-width.\(UUID().uuidString)"))
        let model = AppModel(restoreLastProject: false, supportDirectory: appSupport, defaults: defaults)
        model.openProject(project)
        model.messages = [
            ChatMessage(role: .user, text: "python"),
            ChatMessage(role: .assistant, text: "**结论**：可以。\n\n- 支持 Markdown\n- 窄栏应自动换行")
        ]

        let size = NSSize(width: 360, height: 520)
        let hostingView = NSHostingView(
            rootView: CodexPanel()
                .environmentObject(model)
                .frame(width: size.width, height: size.height)
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        defer {
            window.contentView = nil
            window.close()
        }

        hostingView.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()

        XCTAssertLessThanOrEqual(hostingView.fittingSize.width, size.width + 1)
    }

    @MainActor
    func testCompletionIndexRefreshesAfterSourceEdits() async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceLeaf-xctest-completion-index-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SourceLeaf.xctest-completion-index.\(UUID().uuidString)"))
        defaults.removePersistentDomain(forName: "SourceLeaf.xctest-completion-index")
        let project = support.appendingPathComponent("项目", isDirectory: true)
        let appSupport = support.appendingPathComponent("应用状态", isDirectory: true)
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("figures", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("\\documentclass{article}\n\\label{sec:original}\n".utf8)
            .write(to: project.appendingPathComponent("main.tex"), options: .atomic)
        try Data("@article{smith2024rag, title={RAG}}\n".utf8)
            .write(to: project.appendingPathComponent("refs.bib"), options: .atomic)
        try Data([0x89, 0x50, 0x4E, 0x47])
            .write(to: project.appendingPathComponent("figures/overview.png"), options: .atomic)

        let model = AppModel(restoreLastProject: false, supportDirectory: appSupport, defaults: defaults)
        model.openProject(project)

        XCTAssertTrue(model.completionIndex.labels.keys.contains("sec:original"))
        XCTAssertTrue(model.completionIndex.citations.contains("smith2024rag"))
        XCTAssertTrue(model.completionIndex.includedFiles.contains("figures/overview.png"))

        model.sourceChanged("\\documentclass{article}\n\\label{sec:edited}\n")
        try await Task.sleep(for: .milliseconds(700))

        XCTAssertTrue(model.completionIndex.labels.keys.contains("sec:edited"))
        XCTAssertFalse(model.completionIndex.labels.keys.contains("sec:original"))
    }
}

@MainActor
private final class SourceTypingState: ObservableObject {
    @Published var text: String
    @Published var selection: NSRange

    init(text: String = "", selection: NSRange = NSRange(location: 0, length: 0)) {
        self.text = text
        self.selection = selection
    }
}

@MainActor
private func makeSourceEditorHost(state: SourceTypingState) -> (window: NSWindow, view: NSHostingView<SourceTextView>) {
    let view = NSHostingView(rootView: SourceTextView(
        text: Binding(get: { state.text }, set: { state.text = $0 }),
        selection: Binding(get: { state.selection }, set: { state.selection = $0 }),
        showSelectionButton: false,
        editorTheme: .light,
        editorFontFamily: "Menlo",
        editorFontSize: 14,
        onAskAI: {}
    ))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
        styleMask: [.titled, .resizable],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.makeKeyAndOrderFront(nil)
    view.layoutSubtreeIfNeeded()
    return (window, view)
}

@MainActor
private func closeWindow(_ window: NSWindow) {
    window.contentView = nil
    window.close()
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
private func keyEvent(character: String, keyCode: UInt16, window: NSWindow) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        characters: character,
        charactersIgnoringModifiers: character,
        isARepeat: false,
        keyCode: keyCode
    )
}
