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
    }

    func testFindMatchesReturnEveryOccurrenceForPersistentHighlighting() {
        let matches = SourceFindController.matches(in: "alpha beta Alpha alphabet", query: "alpha")

        XCTAssertEqual(matches.count, 3)
        XCTAssertEqual(matches.map(\.location), [0, 11, 17])
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
