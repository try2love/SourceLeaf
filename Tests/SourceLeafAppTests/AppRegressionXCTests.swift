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
        XCTAssertFalse(ComposerNSTextView.shouldTreatReturnAsSend(
            characters: "\r",
            modifierFlags: [],
            sendBehavior: .enter,
            hasMarkedText: false,
            recentlyTypedWithCompositionInputSource: true
        ))
        XCTAssertTrue(ComposerNSTextView.shouldTreatReturnAsSend(
            characters: "\r",
            modifierFlags: [.shift],
            sendBehavior: .shiftEnter,
            hasMarkedText: false,
            compositionInputSourceActive: true
        ))
    }

    func testChineseInputSourceNamesPreferReturnCommit() {
        XCTAssertTrue(ComposerNSTextView.inputSourcePrefersReturnCommit(sourceID: "com.apple.inputmethod.SCIM.ITABC"))
        XCTAssertTrue(ComposerNSTextView.inputSourcePrefersReturnCommit(sourceID: "com.apple.inputmethod.Pinyin"))
        XCTAssertTrue(ComposerNSTextView.inputSourcePrefersReturnCommit(sourceID: "com.apple.keylayout.ABC", localizedName: "ABC - 简体拼音"))
        XCTAssertFalse(ComposerNSTextView.inputSourcePrefersReturnCommit(sourceID: "com.apple.keylayout.US", languages: ["en"]))
    }

    func testFindMatchesReturnEveryOccurrenceForPersistentHighlighting() {
        let matches = SourceFindController.matches(in: "alpha beta Alpha alphabet", query: "alpha")

        XCTAssertEqual(matches.count, 3)
        XCTAssertEqual(matches.map(\.location), [0, 11, 17])
    }

    func testReplaceAllUsesTheSameCaseInsensitiveMatchesShownByFindHighlights() {
        let source = "alpha beta Alpha alphabet ALPHA"

        let replaced = SourceFindController.replacingAllMatches(in: source, query: "alpha", replacement: "X")

        XCTAssertEqual(replaced, "X beta X Xbet X")
    }

    func testLatexCompletionCandidatesCoverCoreAuthoringCommands() {
        let suggestions = LaTeXCompletionEngine.suggestions(prefix: "\\", source: "\\documentclass{article}")
            .map(\.insertion)

        XCTAssertGreaterThanOrEqual(suggestions.count, 60)
        XCTAssertTrue(suggestions.contains("\\usepackage{}"))
        XCTAssertTrue(suggestions.contains("\\begin{}"))
        XCTAssertTrue(suggestions.contains("\\section{}"))
        XCTAssertTrue(suggestions.contains("\\title{}"))
        XCTAssertTrue(suggestions.contains("\\author{}"))
        XCTAssertTrue(suggestions.contains("\\maketitle"))
        XCTAssertTrue(suggestions.contains("\\begin{align}"))
        XCTAssertTrue(suggestions.contains("\\begin{tabular}{}"))
        XCTAssertTrue(suggestions.contains("\\includegraphics[]{}"))
        XCTAssertTrue(suggestions.contains("\\cite{}"))
        XCTAssertTrue(suggestions.contains("\\bibliography{}"))
        XCTAssertTrue(suggestions.contains("\\footnote{}"))
        XCTAssertTrue(suggestions.contains("\\mathbb{}"))
        XCTAssertTrue(suggestions.contains("\\rightarrow"))
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

    func testLatexArgumentCompletionUsesLocalWindowAndKeepsAbsoluteRange() throws {
        let prefix = String(repeating: "The paper discusses retrieval augmented generation. ", count: 40)
        let source = (prefix + "\\cite{smi") as NSString
        let context = try XCTUnwrap(LaTeXCompletionEngine.argumentContext(
            in: source,
            cursorLocation: source.length
        ))

        XCTAssertEqual(context.command, "cite")
        XCTAssertEqual(context.prefix, "smi")
        XCTAssertEqual(context.range, NSRange(location: source.length - 3, length: 3))
    }

    func testLatexArgumentCompletionIgnoresPlainParagraphTyping() {
        let source = (String(repeating: "plain paragraph typing with no command ", count: 80) + "done") as NSString

        XCTAssertNil(LaTeXCompletionEngine.argumentContext(
            in: source,
            cursorLocation: source.length
        ))
    }

    @MainActor
    func testBackslashShowsSourceLeafLatexCompletionOverlayWithoutMutatingSource() async throws {
        let state = SourceTypingState()
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\\", keyCode: 42, window: host.window)))
        try await Task.sleep(for: .milliseconds(80))

        let overlay = try XCTUnwrap(findCompletionOverlay(in: host.view))
        XCTAssertTrue(overlay.isShowing)
        XCTAssertEqual(textView.string, "\\")
        XCTAssertTrue(overlay.candidates.map(\.insertion).contains("\\section{}"))
        XCTAssertTrue(overlay.candidates.map(\.insertion).contains("\\cite{}"))
    }

    @MainActor
    func testBackslashCompletionKeepsAllCandidatesReachableByKeyboardNavigation() async throws {
        let state = SourceTypingState()
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\\", keyCode: 42, window: host.window)))
        try await Task.sleep(for: .milliseconds(80))

        let overlay = try XCTUnwrap(findCompletionOverlay(in: host.view))
        XCTAssertTrue(overlay.isShowing)
        XCTAssertGreaterThanOrEqual(overlay.candidates.count, 60)

        for _ in 0..<14 {
            textView.doCommand(by: #selector(NSResponder.moveDown(_:)))
        }

        XCTAssertGreaterThanOrEqual(overlay.selectedIndex, 14)
        XCTAssertLessThan(overlay.selectedIndex, overlay.candidates.count)
    }

    @MainActor
    func testTabAcceptsNarrowedLatexCompletionAndPlacesCaretInsideBraces() async throws {
        let state = SourceTypingState()
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)

        for (character, keyCode) in [("\\", 42), ("s", 1), ("e", 14), ("c", 8)] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: host.window)))
            try await Task.sleep(for: .milliseconds(20))
        }
        let overlay = try XCTUnwrap(findCompletionOverlay(in: host.view))
        XCTAssertTrue(overlay.isShowing)
        XCTAssertEqual(overlay.candidates.map(\.insertion), ["\\section{}"])

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\t", keyCode: 48, window: host.window)))
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(textView.string, "\\section{}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 0))
        XCTAssertFalse(overlay.isShowing)
    }

    @MainActor
    func testUndoAfterAcceptingLatexCompletionRestoresTypedPrefixAndCaret() async throws {
        let state = SourceTypingState()
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)

        for (character, keyCode) in [("\\", 42), ("s", 1), ("e", 14), ("c", 8)] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: host.window)))
            try await Task.sleep(for: .milliseconds(20))
        }
        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\t", keyCode: 48, window: host.window)))
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(textView.string, "\\section{}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 0))

        textView.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(textView.string, "\\sec")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 0))
        XCTAssertEqual(state.text, "\\sec")
        XCTAssertEqual(state.selection, NSRange(location: 4, length: 0))

        textView.undoManager?.redo()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(textView.string, "\\section{}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 0))
        XCTAssertEqual(state.text, "\\section{}")
        XCTAssertEqual(state.selection, NSRange(location: 9, length: 0))
    }

    @MainActor
    func testTabJumpsBetweenLatexCompletionPlaceholders() async throws {
        let state = SourceTypingState()
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)

        for (character, keyCode) in [("\\", 42), ("f", 3), ("r", 15)] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: host.window)))
            try await Task.sleep(for: .milliseconds(20))
        }
        let overlay = try XCTUnwrap(findCompletionOverlay(in: host.view))
        XCTAssertTrue(overlay.isShowing)
        XCTAssertEqual(overlay.candidates.first?.insertion, "\\frac{}{}")

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\t", keyCode: 48, window: host.window)))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(textView.string, "\\frac{}{}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 0))

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "x", keyCode: 7, window: host.window)))
        try await Task.sleep(for: .milliseconds(20))
        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\t", keyCode: 48, window: host.window)))
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(textView.string, "\\frac{x}{}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 0))

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "y", keyCode: 16, window: host.window)))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(textView.string, "\\frac{x}{y}")
        XCTAssertEqual(state.selection, NSRange(location: 10, length: 0))
    }

    @MainActor
    func testOptionalArgumentCompletionStartsInOptionalPlaceholderAndTabsToRequiredPlaceholder() async throws {
        let state = SourceTypingState()
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)

        for (character, keyCode) in [("\\", 42), ("i", 34), ("n", 45), ("c", 8)] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: host.window)))
            try await Task.sleep(for: .milliseconds(20))
        }
        let overlay = try XCTUnwrap(findCompletionOverlay(in: host.view))
        XCTAssertTrue(overlay.isShowing)
        XCTAssertEqual(overlay.candidates.first?.insertion, "\\includegraphics[]{}")

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\t", keyCode: 48, window: host.window)))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(textView.string, "\\includegraphics[]{}")
        let optionalRange = (textView.string as NSString).range(of: "[]")
        XCTAssertNotEqual(optionalRange.location, NSNotFound)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: optionalRange.location + 1, length: 0))

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "w", keyCode: 13, window: host.window)))
        try await Task.sleep(for: .milliseconds(20))
        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\t", keyCode: 48, window: host.window)))
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(textView.string, "\\includegraphics[w]{}")
        let requiredRange = (textView.string as NSString).range(of: "{}")
        XCTAssertNotEqual(requiredRange.location, NSNotFound)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: requiredRange.location + 1, length: 0))
    }

    @MainActor
    func testCitationCompletionUsesProjectBibliographyIndex() async throws {
        let state = SourceTypingState()
        let context = LaTeXCompletionContext(index: ProjectIndex(
            rootDocument: nil,
            sectionSummaries: [:],
            labels: [:],
            citations: ["smith2024rag", "zhang2025mutedrag"],
            includedFiles: []
        ))
        let host = makeSourceEditorHost(state: state, completionContext: context)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)

        for (character, keyCode) in [
            ("\\", 42), ("c", 8), ("i", 34), ("t", 17), ("e", 14),
            ("{", 33), ("s", 1), ("m", 46)
        ] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: host.window)))
            try await Task.sleep(for: .milliseconds(20))
        }

        let overlay = try XCTUnwrap(findCompletionOverlay(in: host.view))
        XCTAssertTrue(overlay.isShowing)
        XCTAssertEqual(overlay.candidates.map(\.insertion), ["smith2024rag"])

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\t", keyCode: 48, window: host.window)))
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(textView.string, "\\cite{smith2024rag}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 18, length: 0))
    }

    @MainActor
    func testBeginEnvironmentCompletionInsertsMatchingEndEnvironment() async throws {
        let state = SourceTypingState()
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)

        for (character, keyCode) in [
            ("\\", 42), ("b", 11), ("e", 14), ("g", 5), ("i", 34), ("n", 45),
            ("{", 33), ("f", 3), ("i", 34), ("g", 5)
        ] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: host.window)))
            try await Task.sleep(for: .milliseconds(20))
        }

        let overlay = try XCTUnwrap(findCompletionOverlay(in: host.view))
        XCTAssertTrue(overlay.isShowing)
        XCTAssertEqual(overlay.candidates.first?.insertion, "figure")

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\t", keyCode: 48, window: host.window)))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(textView.string, "\\begin{figure}\n\n\\end{figure}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 15, length: 0))
        XCTAssertFalse(overlay.isShowing)
    }

    @MainActor
    func testUndoAfterBeginEnvironmentCompletionRemovesMatchingEndEnvironmentTogether() async throws {
        let state = SourceTypingState()
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)

        for (character, keyCode) in [
            ("\\", 42), ("b", 11), ("e", 14), ("g", 5), ("i", 34), ("n", 45),
            ("{", 33), ("f", 3), ("i", 34), ("g", 5)
        ] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: host.window)))
            try await Task.sleep(for: .milliseconds(20))
        }

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\t", keyCode: 48, window: host.window)))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(textView.string, "\\begin{figure}\n\n\\end{figure}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 15, length: 0))

        textView.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(textView.string, "\\begin{fig}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 10, length: 0))
        XCTAssertEqual(state.text, "\\begin{fig}")
        XCTAssertEqual(state.selection, NSRange(location: 10, length: 0))

        textView.undoManager?.redo()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(textView.string, "\\begin{figure}\n\n\\end{figure}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 15, length: 0))
        XCTAssertEqual(state.text, "\\begin{figure}\n\n\\end{figure}")
        XCTAssertEqual(state.selection, NSRange(location: 15, length: 0))
    }

    @MainActor
    func testFullBeginEnvironmentCandidateInsertsMatchingEndEnvironment() async throws {
        let state = SourceTypingState()
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)

        for (character, keyCode) in [
            ("\\", 42), ("b", 11), ("e", 14), ("g", 5), ("i", 34), ("n", 45)
        ] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: host.window)))
            try await Task.sleep(for: .milliseconds(20))
        }

        let overlay = try XCTUnwrap(findCompletionOverlay(in: host.view))
        XCTAssertTrue(overlay.isShowing)
        let insertions = overlay.candidates.map(\.insertion)
        let figureIndex = try XCTUnwrap(
            insertions.firstIndex(of: "\\begin{figure}"),
            "Missing figure environment candidate. Candidates: \(insertions.joined(separator: " | "))"
        )

        overlay.onPick?(figureIndex)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(textView.string, "\\begin{figure}\n\n\\end{figure}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 15, length: 0))
        XCTAssertEqual(state.selection, NSRange(location: 15, length: 0))
    }

    @MainActor
    func testEscapeDismissesLatexCompletionOverlay() async throws {
        let state = SourceTypingState()
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)
        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\\", keyCode: 42, window: host.window)))
        try await Task.sleep(for: .milliseconds(80))
        let overlay = try XCTUnwrap(findCompletionOverlay(in: host.view))
        XCTAssertTrue(overlay.isShowing)

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\u{1b}", keyCode: 53, window: host.window)))
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertFalse(overlay.isShowing)
        XCTAssertEqual(textView.string, "\\")
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
    func testSourceSelectionBindingAdvancesOnEveryKeystroke() async throws {
        let state = SourceTypingState(text: "alpha omega", selection: NSRange(location: 6, length: 0))
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        state.selection = NSRange(location: 6, length: 0)

        var expectedLocation = 6
        for (character, keyCode) in [("t", 17), ("e", 14), ("s", 1), ("t", 17)] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: host.window)))
            expectedLocation += 1
            XCTAssertEqual(textView.selectedRange(), NSRange(location: expectedLocation, length: 0))
            XCTAssertEqual(state.selection, NSRange(location: expectedLocation, length: 0))
        }

        XCTAssertEqual(textView.string, "alpha testomega")
        XCTAssertEqual(state.text, "alpha testomega")
    }

    @MainActor
    func testSourcePanelEditingKeepsCaretMovingInsideARealProjectModel() async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceLeaf-xctest-real-editor-caret-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let project = support.appendingPathComponent("项目", isDirectory: true)
        let appSupport = support.appendingPathComponent("应用状态", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let body = Array(
            repeating: "\\section{Caret Stress} Some source with \\cite{paper} and \\label{sec:stress}.",
            count: 1_200
        ).joined(separator: "\n")
        try Data("\\documentclass{article}\n\\begin{document}\n\(body)\n\\end{document}\n".utf8)
            .write(to: project.appendingPathComponent("main.tex"), options: .atomic)
        try Data("@article{paper,title={Stress}}\n".utf8)
            .write(to: project.appendingPathComponent("refs.bib"), options: .atomic)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SourceLeaf.xctest-real-editor-caret.\(UUID().uuidString)"))
        let model = AppModel(restoreLastProject: false, supportDirectory: appSupport, defaults: defaults)
        model.openProject(project)
        model.configuration.build.autoBuild = false
        model.configuration.autoSave = false
        model.selectedRange = NSRange(location: 0, length: 0)

        let view = NSHostingView(rootView: SourcePanel().environmentObject(model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { closeWindow(window) }
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(450))

        let textView = try XCTUnwrap(findSourceTextView(in: view))
        let overlay = try XCTUnwrap(findCompletionOverlay(in: view))
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        model.selectedRange = NSRange(location: 0, length: 0)

        var expected = ""
        for (character, keyCode) in [("t", 17), ("e", 14), ("s", 1), ("t", 17)] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: window)))
            expected.append(character)
            try await Task.sleep(for: .milliseconds(10))
            XCTAssertEqual(textView.selectedRange(), NSRange(location: (expected as NSString).length, length: 0))
            XCTAssertEqual(model.selectedRange, NSRange(location: (expected as NSString).length, length: 0))
        }
        XCTAssertTrue(textView.string.hasPrefix("test"))

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\\", keyCode: 42, window: window)))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertTrue(overlay.isShowing)
        XCTAssertTrue(overlay.candidates.map(\.insertion).contains("\\section{}"))

        for (character, keyCode) in [("s", 1), ("e", 14), ("c", 8)] {
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: window)))
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual((textView.string as NSString).substring(with: NSRange(location: 0, length: 8)), "test\\sec")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 8, length: 0))
        XCTAssertEqual(model.selectedRange, NSRange(location: 8, length: 0))

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\u{7f}", keyCode: 51, window: window)))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual((textView.string as NSString).substring(with: NSRange(location: 0, length: 7)), "test\\se")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 7, length: 0))
        XCTAssertEqual(model.selectedRange, NSRange(location: 7, length: 0))
    }

    @MainActor
    func testSourcePanelIgnoresDelayedStaleSelectionEchoesDuringTyping() async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceLeaf-xctest-stale-panel-selection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let project = support.appendingPathComponent("项目", isDirectory: true)
        let appSupport = support.appendingPathComponent("应用状态", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("\\documentclass{article}\n\\begin{document}\nalpha omega\n\\end{document}\n".utf8)
            .write(to: project.appendingPathComponent("main.tex"), options: .atomic)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SourceLeaf.xctest-stale-panel-selection.\(UUID().uuidString)"))
        let model = AppModel(restoreLastProject: false, supportDirectory: appSupport, defaults: defaults)
        model.openProject(project)
        model.configuration.build.autoBuild = false
        model.configuration.autoSave = false

        let view = NSHostingView(rootView: SourcePanel().environmentObject(model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 440),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { closeWindow(window) }
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(450))

        let textView = try XCTUnwrap(findSourceTextView(in: view))
        let insertion = (textView.string as NSString).range(of: "omega").location
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: insertion, length: 0))
        model.selectedRange = NSRange(location: insertion, length: 0)

        var expectedLocation = insertion
        for (character, keyCode) in [("t", 17), ("e", 14), ("s", 1), ("t", 17)] {
            let stale = NSRange(location: expectedLocation, length: 0)
            textView.keyDown(with: try XCTUnwrap(keyEvent(character: character, keyCode: UInt16(keyCode), window: window)))
            expectedLocation += 1
            model.selectedRange = stale
            try await Task.sleep(for: .milliseconds(24))
            XCTAssertEqual(textView.selectedRange(), NSRange(location: expectedLocation, length: 0))
            XCTAssertEqual(model.selectedRange, NSRange(location: expectedLocation, length: 0))
        }

        XCTAssertTrue(textView.string.contains("alpha testomega"))
        XCTAssertFalse(textView.string.contains("alpha tsetomega"))
    }

    @MainActor
    func testFigureCommandCanInsertAProjectImageTemplateAndSelectCaption() async throws {
        let request = LaTeXEditRequest(command: .figure, argument: "figures/overview.png")
        let state = SourceTypingState(commandRequest: request)
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(450))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertTrue(textView.string.contains("\\includegraphics[width=\\linewidth]{figures/overview.png}"))
        XCTAssertTrue(textView.string.contains("\\caption{Caption}"))
        XCTAssertEqual((textView.string as NSString).substring(with: textView.selectedRange()), "Caption")
        XCTAssertNil(state.commandRequest)
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

    @MainActor
    func testBackspaceBetweenAutoInsertedSmartPairDeletesBothDelimiters() async throws {
        let state = SourceTypingState()
        let host = makeSourceEditorHost(state: state)
        defer { closeWindow(host.window) }
        try await Task.sleep(for: .milliseconds(350))
        let textView = try XCTUnwrap(findSourceTextView(in: host.view))
        host.window.makeFirstResponder(textView)

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "{", keyCode: 33, window: host.window)))
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(textView.string, "{}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 0))

        textView.keyDown(with: try XCTUnwrap(keyEvent(character: "\u{7f}", keyCode: 51, window: host.window)))
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(textView.string, "")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertEqual(state.text, "")
        XCTAssertEqual(state.selection, NSRange(location: 0, length: 0))

        textView.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(textView.string, "{}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 2))
        XCTAssertEqual(state.text, "{}")

        textView.undoManager?.redo()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(textView.string, "")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertEqual(state.text, "")
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
    @Published var commandRequest: LaTeXEditRequest?

    init(text: String = "", selection: NSRange = NSRange(location: 0, length: 0), commandRequest: LaTeXEditRequest? = nil) {
        self.text = text
        self.selection = selection
        self.commandRequest = commandRequest
    }
}

@MainActor
private func makeSourceEditorHost(
    state: SourceTypingState,
    completionContext: LaTeXCompletionContext = LaTeXCompletionContext()
) -> (window: NSWindow, view: NSHostingView<SourceTextView>) {
    let view = NSHostingView(rootView: SourceTextView(
        text: Binding(get: { state.text }, set: { state.text = $0 }),
        selection: Binding(get: { state.selection }, set: { state.selection = $0 }),
        completionContext: completionContext,
        commandRequest: state.commandRequest,
        showSelectionButton: false,
        editorTheme: .light,
        editorFontFamily: "Menlo",
        editorFontSize: 14,
        onAskAI: {},
        onCommandApplied: { id in
            if state.commandRequest?.id == id { state.commandRequest = nil }
        }
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
private func findCompletionOverlay(in view: NSView) -> LaTeXCompletionOverlayView? {
    if let overlay = view as? LaTeXCompletionOverlayView {
        return overlay
    }
    for child in view.subviews {
        if let match = findCompletionOverlay(in: child) { return match }
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
