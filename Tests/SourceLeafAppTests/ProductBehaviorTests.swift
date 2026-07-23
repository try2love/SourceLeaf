import Foundation
import SourceLeafCore
import Testing
@testable import SourceLeafApp

@MainActor
@Test func customizedPromptPersistsAcrossApplicationModels() throws {
    let state = try productTestState(named: "prompts")
    defer { state.cleanup() }
    let first = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    let prompt = first.addPrompt()
    let index = try #require(first.promptTemplates.firstIndex { $0.id == prompt.id })
    first.promptTemplates[index].nameZH = "压缩论文摘要"
    first.promptTemplates[index].bodyZH = "保留事实与引用，只压缩冗余表达。"
    first.promptTemplates[index].enabled = false
    first.savePromptTemplates()

    let restored = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    let saved = try #require(restored.promptTemplates.first { $0.id == prompt.id })
    #expect(saved.nameZH == "压缩论文摘要")
    #expect(saved.bodyZH == "保留事实与引用，只压缩冗余表达。")
    #expect(!saved.enabled)
    #expect(!saved.builtIn)
}

@MainActor
@Test func applicationRestoresTheLastProjectAndSourceFile() throws {
    guard let fixturesPath = ProcessInfo.processInfo.environment["SOURCELEAF_BOUNDARY_PROJECTS"] else { return }
    let state = try productTestState(named: "restore")
    defer { state.cleanup() }
    let project = URL(fileURLWithPath: fixturesPath, isDirectory: true)
        .appendingPathComponent("多文件论文", isDirectory: true)
    let first = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    first.openProject(project)
    let details = try #require(first.projectFiles.first { $0.relativePath == "sections/deep/details.tex" })
    first.openFile(details)

    let restored = AppModel(restoreLastProject: true, supportDirectory: state.support, defaults: state.defaults)
    #expect(restored.projectRoot?.standardizedFileURL == project.standardizedFileURL)
    #expect(restored.selectedFile?.relativePath == "sections/deep/details.tex")
}

@MainActor
@Test func applicationRecoversToSourceAfterThePreviousRestoreCrashedOnAnImage() throws {
    guard let projectPath = ProcessInfo.processInfo.environment["SOURCELEAF_REAL_PROJECT"] else { return }
    let state = try productTestState(named: "restore-crash-recovery")
    defer { state.cleanup() }
    let project = URL(fileURLWithPath: projectPath, isDirectory: true)
    let first = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    first.openProject(project)
    let photo = try #require(first.projectFiles.first { $0.relativePath == "figures/author/LiweiLiu.jpg" })
    first.openFile(photo)
    #expect(first.selectedImageFile?.relativePath == photo.relativePath)
    state.defaults.set(true, forKey: "SourceLeaf.restoreInProgress")

    let recovered = AppModel(restoreLastProject: true, supportDirectory: state.support, defaults: state.defaults)
    let projectKey = String(SourceTargetService.hash(project.standardizedFileURL.path).prefix(16))

    #expect(recovered.projectRoot?.standardizedFileURL == project.standardizedFileURL)
    #expect(recovered.selectedFile?.kind == .tex)
    #expect(recovered.layout.selected[.center] == .source)
    #expect(state.defaults.string(forKey: "SourceLeaf.lastFile.\(projectKey)") != photo.relativePath)
}

@MainActor
@Test func detachedPanelReturnsToTheMainWorkspaceWhenItsWindowCloses() throws {
    let state = try productTestState(named: "floating")
    defer { state.cleanup() }
    let model = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    let originalZone = model.layout.zone(containing: .pdf)
    model.detachPanel(.pdf)
    #expect(model.floatingPanels.contains(.pdf))
    #expect(!model.layout.contains(.pdf))

    model.restoreFloatingPanel(.pdf)
    #expect(!model.floatingPanels.contains(.pdf))
    #expect(model.layout.zone(containing: .pdf) == originalZone)
}

@MainActor
@Test func selectedConversationProviderPersistsAcrossLaunches() throws {
    let state = try productTestState(named: "selected-provider")
    defer { state.cleanup() }
    let first = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    let profile = ProviderProfile(
        name: "Lab API",
        kind: .openAICompatible,
        model: "research-model",
        baseURL: "http://127.0.0.1:1234/v1/chat/completions",
        reasoningEffort: .high
    )
    first.providerProfiles.append(profile)
    first.saveProviderProfiles()
    first.selectProvider(profile.id)

    let restored = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    #expect(restored.selectedProviderID == profile.id)
    #expect(restored.selectedProviderModel == "research-model")
    #expect(restored.selectedReasoningEffort == .high)
}

@MainActor
@Test func explicitSaveWritesTheCurrentSourceAndClearsDirtyState() throws {
    let state = try productTestState(named: "manual-save")
    defer { state.cleanup() }
    let project = state.support.appendingPathComponent("项目", isDirectory: true)
    let appSupport = state.support.appendingPathComponent("应用状态", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let sourceURL = project.appendingPathComponent("main.tex")
    let original = "\\documentclass{article}\n\\begin{document}\nOriginal\n\\end{document}\n"
    try Data(original.utf8).write(to: sourceURL, options: .atomic)

    let model = AppModel(restoreLastProject: false, supportDirectory: appSupport, defaults: state.defaults)
    model.openProject(project)
    let edited = original.replacingOccurrences(of: "Original", with: "Saved explicitly")
    model.sourceChanged(edited)

    #expect(model.canSaveCurrentFile)
    #expect(model.hasUnsavedChanges)
    model.saveNow()
    let saved = try String(contentsOf: sourceURL, encoding: .utf8)
    #expect(!model.hasUnsavedChanges)
    #expect(saved == edited)
}

@Test func latexFormattingTogglesLineCommentsAcrossSelectedLines() throws {
    let source = "alpha\n  beta\n\n% already\n"
    let selectedLength = ("alpha\n  beta\n" as NSString).length
    let commented = LaTeXSourceFormatter.edit(
        command: .toggleComment,
        source: source,
        selection: NSRange(location: 0, length: selectedLength)
    )

    #expect(commented.replacementRange == NSRange(location: 0, length: selectedLength))
    #expect(commented.replacement == "% alpha\n  % beta\n")
    #expect(commented.resultingSelection == NSRange(location: 0, length: ("% alpha\n  % beta\n" as NSString).length))

    let next = (source as NSString).replacingCharacters(in: commented.replacementRange, with: commented.replacement)
    let uncommented = LaTeXSourceFormatter.edit(
        command: .toggleComment,
        source: next,
        selection: commented.resultingSelection
    )

    #expect(uncommented.replacement == "alpha\n  beta\n")
    #expect(uncommented.resultingSelection == NSRange(location: 0, length: selectedLength))
}

@Test func latexFormattingIndentsAndOutdentsSelectedLines() throws {
    let source = "alpha\n  beta\n"
    let fullSelection = NSRange(location: 0, length: (source as NSString).length)
    let indented = LaTeXSourceFormatter.edit(
        command: .indentLines,
        source: source,
        selection: fullSelection
    )

    #expect(indented.replacementRange == fullSelection)
    #expect(indented.replacement == "  alpha\n    beta\n")
    #expect(indented.resultingSelection == NSRange(location: 0, length: ("  alpha\n    beta\n" as NSString).length))

    let next = (source as NSString).replacingCharacters(in: indented.replacementRange, with: indented.replacement)
    let outdented = LaTeXSourceFormatter.edit(
        command: .outdentLines,
        source: next,
        selection: indented.resultingSelection
    )

    #expect(outdented.replacement == source)
    #expect(outdented.resultingSelection == fullSelection)
}

@Test func latexNewlinePreservesIndentAndContinuesListItems() throws {
    let environmentSource = "\\begin{itemize}"
    let environmentEdit = LaTeXSourceFormatter.newlineEdit(
        source: environmentSource,
        selection: NSRange(location: (environmentSource as NSString).length, length: 0)
    )
    #expect(environmentEdit.replacement == "\n  \\item ")

    let itemSource = "  \\item First"
    let itemEdit = LaTeXSourceFormatter.newlineEdit(
        source: itemSource,
        selection: NSRange(location: (itemSource as NSString).length, length: 0)
    )
    #expect(itemEdit.replacement == "\n  \\item ")

    let figureSource = "  \\begin{figure}"
    let figureEdit = LaTeXSourceFormatter.newlineEdit(
        source: figureSource,
        selection: NSRange(location: (figureSource as NSString).length, length: 0)
    )
    #expect(figureEdit.replacement == "\n    ")
}

@MainActor
@Test func latexCompletionIndexRefreshesAfterProjectOpenAndSourceEditsWithoutBodyScanning() async throws {
    let state = try productTestState(named: "completion-index")
    defer { state.cleanup() }
    let project = state.support.appendingPathComponent("项目", isDirectory: true)
    let appSupport = state.support.appendingPathComponent("应用状态", isDirectory: true)
    try FileManager.default.createDirectory(at: project.appendingPathComponent("figures", isDirectory: true), withIntermediateDirectories: true)
    let sourceURL = project.appendingPathComponent("main.tex")
    try Data("\\documentclass{article}\n\\label{sec:original}\n".utf8).write(to: sourceURL, options: .atomic)
    try Data("@article{smith2024rag, title={RAG}}\n".utf8).write(to: project.appendingPathComponent("refs.bib"), options: .atomic)
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: project.appendingPathComponent("figures/overview.png"), options: .atomic)

    let model = AppModel(restoreLastProject: false, supportDirectory: appSupport, defaults: state.defaults)
    model.openProject(project)

    #expect(model.completionIndex.labels.keys.contains("sec:original"))
    #expect(model.completionIndex.citations.contains("smith2024rag"))
    #expect(model.completionIndex.includedFiles.contains("figures/overview.png"))

    model.sourceChanged("\\documentclass{article}\n\\label{sec:edited}\n")
    for _ in 0..<40 where !model.completionIndex.labels.keys.contains("sec:edited") {
        try await Task.sleep(for: .milliseconds(50))
    }

    #expect(model.completionIndex.labels.keys.contains("sec:edited"))
    #expect(!model.completionIndex.labels.keys.contains("sec:original"))
}

@MainActor
@Test func manualSaveModeBlocksAutomaticCompilationUntilSourceIsSaved() throws {
    let state = try productTestState(named: "manual-save-auto-build")
    defer { state.cleanup() }
    let project = state.support.appendingPathComponent("项目", isDirectory: true)
    let appSupport = state.support.appendingPathComponent("应用状态", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("\\documentclass{article}\nChanged\n".utf8).write(to: project.appendingPathComponent("main.tex"))
    let model = AppModel(restoreLastProject: false, supportDirectory: appSupport, defaults: state.defaults)
    model.openProject(project)
    model.setAutoSave(false)
    #expect(!model.configuration.build.autoBuild)
    model.setAutoBuild(true)
    #expect(!model.configuration.build.autoBuild)
    model.sourceChanged(model.sourceText + "more")

    #expect(model.hasUnsavedChanges)
    #expect(!model.canAutoCompileCurrentSource)
    model.saveNow()
    #expect(!model.canAutoCompileCurrentSource)
}

@MainActor
@Test func chatSessionsRecordAIConfigurationBeforeConversationContent() throws {
    let state = try productTestState(named: "chat-configuration-notice")
    defer { state.cleanup() }
    let project = state.support.appendingPathComponent("项目", isDirectory: true)
    let appSupport = state.support.appendingPathComponent("应用状态", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("\\documentclass{article}".utf8).write(to: project.appendingPathComponent("main.tex"))

    let model = AppModel(restoreLastProject: false, supportDirectory: appSupport, defaults: state.defaults)
    model.openProject(project)
    model.newChatSession()

    let first = try #require(model.messages.first)
    #expect(first.role == .system)
    #expect(first.text.hasPrefix(AppModel.aiConfigurationPrefix))
    #expect(first.text.contains("Local Codex"))
}

@MainActor
@Test func internalChatNoticesAreIdentifiedForContextFiltering() throws {
    let activity = ChatMessage(role: .system, text: AppModel.aiActivityPrefix + "Started")
    let config = ChatMessage(role: .system, text: AppModel.aiConfigurationPrefix + "AI: Local Codex")
    let health = ChatMessage(role: .system, text: AppModel.aiHealthPrefix + "AI: Local Codex\nTest status: available")
    let userVisibleSystem = ChatMessage(role: .system, text: "System text from user history")

    #expect(AppModel.isInternalChatNotice(activity))
    #expect(AppModel.isInternalChatNotice(config))
    #expect(AppModel.isInternalChatNotice(health))
    #expect(!AppModel.isInternalChatNotice(userVisibleSystem))
}

@MainActor
@Test func providerHealthChecksArePrintedIntoTheConversationHistory() throws {
    let state = try productTestState(named: "provider-health-chat-message")
    defer { state.cleanup() }
    let project = state.support.appendingPathComponent("项目", isDirectory: true)
    let appSupport = state.support.appendingPathComponent("应用状态", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("\\documentclass{article}".utf8).write(to: project.appendingPathComponent("main.tex"))

    let model = AppModel(restoreLastProject: false, supportDirectory: appSupport, defaults: state.defaults)
    model.openProject(project)
    model.newChatSession()
    model.appendAIHealthMessage(status: .checking)

    let last = try #require(model.messages.last)
    #expect(last.role == .system)
    #expect(last.text.hasPrefix(AppModel.aiHealthPrefix))
    #expect(last.text.contains("Local Codex"))
    #expect(last.text.contains("Testing") || last.text.contains("正在测试"))
}

@MainActor
@Test func conversationsCanBeCreatedRenamedSelectedAndRestored() throws {
    let state = try productTestState(named: "chat-sessions")
    defer { state.cleanup() }
    let project = state.support.appendingPathComponent("项目", isDirectory: true)
    let appSupport = state.support.appendingPathComponent("应用状态", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("\\documentclass{article}".utf8).write(to: project.appendingPathComponent("main.tex"))
    let first = AppModel(restoreLastProject: false, supportDirectory: appSupport, defaults: state.defaults)
    first.openProject(project)
    let originalID = try #require(first.selectedChatSessionID)
    first.newChatSession()
    let newID = try #require(first.selectedChatSessionID)
    #expect(newID != originalID)
    first.renameSelectedChatSession("Methods discussion")
    first.selectChatSession(originalID)
    first.selectChatSession(newID)

    let restored = AppModel(restoreLastProject: false, supportDirectory: appSupport, defaults: state.defaults)
    restored.openProject(project)
    #expect(restored.chatSessions.contains { $0.title == "Methods discussion" })
    #expect(restored.chatSessions.count == 2)
    #expect(restored.selectedChatSessionID == newID)
}

@MainActor
@Test func regeneratingAnOlderAssistantResponseUsesItsOwnUserPrompt() throws {
    let state = try productTestState(named: "message-specific-regeneration")
    defer { state.cleanup() }
    let model = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    let firstUser = ChatMessage(role: .user, text: "Explain the threat model")
    let firstAssistant = ChatMessage(role: .assistant, text: "First answer")
    let secondUser = ChatMessage(role: .user, text: "Now rewrite the conclusion")
    let secondAssistant = ChatMessage(role: .assistant, text: "Second answer")
    model.messages = [firstUser, firstAssistant, secondUser, secondAssistant]

    #expect(model.prepareRegeneration(after: firstAssistant.id))
    #expect(model.instruction == firstUser.text)
    #expect(model.messages.isEmpty)
}

@MainActor
@Test func preparingAHistoryRestoreActivatesTheReviewPanel() throws {
    let state = try productTestState(named: "history-review-activation")
    defer { state.cleanup() }
    let project = state.support.appendingPathComponent("项目", isDirectory: true)
    let appSupport = state.support.appendingPathComponent("应用状态", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("Accepted replacement".utf8).write(to: project.appendingPathComponent("main.tex"))
    let model = AppModel(restoreLastProject: false, supportDirectory: appSupport, defaults: state.defaults)
    model.openProject(project)
    model.revealPanel(.pdf, in: .trailing)
    let trailing = try #require(model.layout.zone(containing: .codex))
    model.layout.selected[trailing] = .pdf
    let entry = AIEditHistoryEntry(
        projectPath: project.path,
        relativePath: "main.tex",
        originalText: "Original text",
        replacementText: "Accepted replacement",
        instruction: "Revise",
        providerName: "Test"
    )

    model.prepareRevert(entry)

    #expect(model.pendingProposal?.replacements.first?.replacement == "Original text")
    #expect(model.layout.selected[trailing] == .codex)
}

@MainActor
@Test func customContextDoesNotLeakAcrossProjects() throws {
    let state = try productTestState(named: "project-context-isolation")
    defer { state.cleanup() }
    let appSupport = state.support.appendingPathComponent("应用状态", isDirectory: true)
    let firstProject = state.support.appendingPathComponent("项目一", isDirectory: true)
    let secondProject = state.support.appendingPathComponent("项目二", isDirectory: true)
    try FileManager.default.createDirectory(at: firstProject, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondProject, withIntermediateDirectories: true)
    try Data("First".utf8).write(to: firstProject.appendingPathComponent("main.tex"))
    try Data("Second".utf8).write(to: secondProject.appendingPathComponent("main.tex"))
    let model = AppModel(restoreLastProject: false, supportDirectory: appSupport, defaults: state.defaults)
    model.openProject(firstProject)
    model.customContextPaths.insert("main.tex")

    model.openProject(secondProject)

    #expect(model.customContextPaths.isEmpty)
}

@MainActor
@Test func changingProviderConfigurationInvalidatesTheHealthCheck() throws {
    let state = try productTestState(named: "provider-health-invalidation")
    defer { state.cleanup() }
    let model = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    let id = try #require(model.selectedProviderID)
    model.setProviderHealth(.connected, for: id)
    #expect(model.selectedProviderHealth == .connected)

    model.selectedProviderModel = "different-model"

    #expect(model.selectedProviderHealth == .unknown)
}

@MainActor
@Test func openingAProjectPDFUsesTheMultipagePDFPanel() throws {
    let state = try productTestState(named: "project-pdf")
    defer { state.cleanup() }
    let project = state.support.appendingPathComponent("项目", isDirectory: true)
    let appSupport = state.support.appendingPathComponent("应用状态", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("\\documentclass{article}".utf8).write(to: project.appendingPathComponent("main.tex"))
    let pdfURL = project.appendingPathComponent("paper.pdf")
    try Data("%PDF-1.4".utf8).write(to: pdfURL)
    let model = AppModel(restoreLastProject: false, supportDirectory: appSupport, defaults: state.defaults)
    model.openProject(project)
    let pdf = try #require(model.projectFiles.first { $0.kind == .pdf })
    model.openFile(pdf)
    #expect(model.pdfURL?.standardizedFileURL == pdfURL.standardizedFileURL)
    #expect(model.layout.contains(.pdf))
}

@MainActor
@Test func documentOutlineExpansionPersistsAcrossApplicationModels() throws {
    let state = try productTestState(named: "outline-expansion")
    defer { state.cleanup() }
    let first = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    #expect(first.projectOutlineExpanded)
    first.toggleProjectOutline()
    #expect(!first.projectOutlineExpanded)

    let restored = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    #expect(!restored.projectOutlineExpanded)
    restored.toggleProjectOutline()
    #expect(restored.projectOutlineExpanded)
}

@MainActor
@Test func editorAppearanceAndTypographyPersistAcrossApplicationModels() throws {
    let state = try productTestState(named: "editor-appearance")
    defer { state.cleanup() }
    let first = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    first.setEditorTheme(.dark)
    first.setEditorFontFamily("Menlo")
    first.setEditorFontSize(17)
    first.setInterfaceFontScale(1.45)

    let restored = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    #expect(restored.editorTheme == .dark)
    #expect(restored.editorFontFamily == "Menlo")
    #expect(restored.editorFontSize == 17)
    #expect(restored.interfaceFontScale == 1.45)
    #expect(InterfaceFontScale.dynamicTypeSize(for: 1) == .large)
    #expect(InterfaceFontScale.dynamicTypeSize(for: restored.interfaceFontScale) == .xxxLarge)
}

@MainActor
@Test func openingAProjectRestoresItsLastSuccessfulPDF() async throws {
    let state = try productTestState(named: "cached-pdf")
    defer { state.cleanup() }
    let project = state.support.appendingPathComponent("项目", isDirectory: true)
    let appSupport = state.support.appendingPathComponent("应用状态", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("\\documentclass{article}\n\\begin{document}Cached\\end{document}\n".utf8)
        .write(to: project.appendingPathComponent("main.tex"))
    let compiler = CompilerService()
    let build = try await compiler.build(
        projectRoot: project,
        rootDocument: "main.tex",
        configuration: BuildConfiguration(
            engine: .custom,
            customCommand: "/usr/bin/touch {{output}}/main.pdf",
            autoBuild: false
        )
    )
    defer { try? FileManager.default.removeItem(at: build.outputDirectory) }

    let model = AppModel(
        restoreLastProject: false,
        supportDirectory: appSupport,
        defaults: state.defaults,
        compiler: compiler
    )
    model.openProject(project)
    for _ in 0..<30 where model.pdfURL == nil {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(model.pdfURL == build.pdfURL)
    #expect(model.buildSucceeded == true)
    #expect(model.buildPhase == .finished)
}

private struct ProductTestState {
    var support: URL
    var defaults: UserDefaults
    var suiteName: String

    func cleanup() {
        try? FileManager.default.removeItem(at: support)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private func productTestState(named name: String) throws -> ProductTestState {
    let base: URL
    if let configured = ProcessInfo.processInfo.environment["SOURCELEAF_TEST_ARTIFACT_ROOT"] {
        base = URL(fileURLWithPath: configured, isDirectory: true)
    } else {
        base = FileManager.default.temporaryDirectory
    }
    let support = base.appendingPathComponent("产品状态-\(name)-\(UUID().uuidString)", isDirectory: true)
    let suiteName = "SourceLeaf.product.\(name).\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    return ProductTestState(support: support, defaults: defaults, suiteName: suiteName)
}
