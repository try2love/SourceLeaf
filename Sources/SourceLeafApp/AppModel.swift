import AppKit
import Combine
import Foundation
import SourceLeafCore

struct PDFNavigationTarget: Equatable, Identifiable {
    var id = UUID()
    var pageIndex: Int
    var x: Double
    var yFromTop: Double
}

enum ProviderHealthStatus: Equatable {
    case unknown
    case checking
    case connected
    case unavailable(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var projectRoot: URL?
    @Published var projectFiles: [ProjectFile] = []
    @Published var projectTree: [ProjectTreeNode] = []
    @Published var selectedFile: ProjectFile?
    @Published var selectedImageFile: ProjectFile?
    @Published var sourceText = ""
    @Published private(set) var hasUnsavedChanges = false
    @Published var selectedRange = NSRange(location: 0, length: 0)
    @Published var pendingLaTeXEdit: LaTeXEditRequest?
    @Published var outline: [DocumentOutlineItem] = []
    @Published var configuration = ProjectConfiguration()
    @Published var layout = DockLayout()
    @Published var pdfURL: URL?
    @Published var pdfSelection = ""
    @Published var pdfPageIndex = 0
    @Published var pdfPageCount = 0
    @Published var pdfNavigationTarget: PDFNavigationTarget?
    @Published var syncTeXDocument: SyncTeXDocument?
    @Published var buildLog = ""
    @Published var buildRunning = false
    @Published var buildSucceeded: Bool?
    @Published var buildPhase: BuildPhase = .idle
    @Published var messages: [ChatMessage] = []
    @Published var editTargets: [SourceTarget] = []
    @Published var pendingProposal: AIProposal?
    @Published var proposalValidation: [UUID: LaTeXValidationResult] = [:]
    @Published var instruction = ""
    @Published var contextScope: ContextScope = .section
    @Published var customContextPaths: Set<String> = []
    @Published var providerProfiles: [ProviderProfile] = [.localCodex]
    @Published var selectedProviderID: UUID?
    @Published private(set) var providerHealth: [UUID: ProviderHealthStatus] = [:]
    @Published var generating = false
    @Published var validatingReplacementID: UUID?
    @Published var lastError: String?
    @Published var history: [AIEditHistoryEntry] = []
    @Published var promptTemplates: [PromptTemplate] = BuiltInPrompts.all
    @Published var selectedPromptID: String?
    @Published var statusText = ""
    @Published var appLanguage: AppLanguage
    @Published var projectOutlineExpanded: Bool
    @Published var editorTheme: EditorTheme = .system
    @Published var editorFontFamily = EditorFontCatalog.systemMonospaced
    @Published var editorFontSize: Double = 13
    @Published private(set) var floatingPanels: Set<WorkspacePanel> = []

    var selectedProviderModel: String {
        get { selectedProviderProfile?.model ?? "" }
        set { updateSelectedProvider { $0.model = newValue } }
    }

    var selectedReasoningEffort: ModelReasoningEffort? {
        get { selectedProviderProfile?.reasoningEffort }
        set { updateSelectedProvider { $0.reasoningEffort = newValue } }
    }

    var selectedProviderKind: ProviderKind? { selectedProviderProfile?.kind }
    var selectedProviderHealth: ProviderHealthStatus {
        guard let selectedProviderID else { return .unknown }
        return providerHealth[selectedProviderID] ?? .unknown
    }

    var canSaveCurrentFile: Bool {
        guard let selectedFile else { return false }
        return [.tex, .bibliography, .style].contains(selectedFile.kind)
    }

    private let compiler: CompilerService
    private let keychain = KeychainStore()
    private var saveTask: Task<Void, Never>?
    private var compileDebounceTask: Task<Void, Never>?
    private var activeCompileTask: Task<Void, Never>?
    private var suppressTextChange = false
    private var projectConfigStore: JSONFileStore<ProjectConfiguration>?
    private var historyStore: JSONFileStore<[AIEditHistoryEntry]>?
    private var profilesStore: JSONFileStore<[ProviderProfile]>?
    private var chatStore: JSONFileStore<[ChatMessage]>?
    private var promptsStore: JSONFileStore<[PromptTemplate]>?
    private var floatingOrigins: [WorkspacePanel: DockZone] = [:]
    private let supportDirectoryOverride: URL?
    private let defaults: UserDefaults
    private static let lastProjectPathKey = "SourceLeaf.lastProjectPath"
    private static let selectedProviderIDKey = "SourceLeaf.selectedProviderID"
    private static let projectOutlineExpandedKey = "SourceLeaf.projectOutlineExpanded"
    private static let editorThemeKey = "SourceLeaf.editorTheme"
    private static let editorFontFamilyKey = "SourceLeaf.editorFontFamily"
    private static let editorFontSizeKey = "SourceLeaf.editorFontSize"

    init(
        restoreLastProject: Bool = true,
        supportDirectory: URL? = nil,
        defaults: UserDefaults = .standard,
        compiler: CompilerService = CompilerService()
    ) {
        self.compiler = compiler
        supportDirectoryOverride = supportDirectory
        self.defaults = defaults
        projectOutlineExpanded = defaults.object(forKey: Self.projectOutlineExpandedKey) == nil
            ? true
            : defaults.bool(forKey: Self.projectOutlineExpandedKey)
        appLanguage = defaults.string(forKey: L10n.languageDefaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? L10n.selectedLanguage
        editorTheme = defaults.string(forKey: Self.editorThemeKey)
            .flatMap(EditorTheme.init(rawValue:)) ?? .system
        editorFontFamily = defaults.string(forKey: Self.editorFontFamilyKey)
            ?? EditorFontCatalog.systemMonospaced
        let savedFontSize = defaults.double(forKey: Self.editorFontSizeKey)
        editorFontSize = savedFontSize == 0 ? 13 : min(32, max(10, savedFontSize))
        do {
            let support = try resolvedSupportDirectory()
            profilesStore = JSONFileStore(url: support.appendingPathComponent("settings/providers.json"))
            promptsStore = JSONFileStore(url: support.appendingPathComponent("settings/prompts.json"))
            providerProfiles = try profilesStore?.load(default: [.localCodex]) ?? [.localCodex]
            if !providerProfiles.contains(where: { $0.kind == .localCodex }) {
                providerProfiles.insert(.localCodex, at: 0)
            }
            if !providerProfiles.contains(where: { $0.kind == .codeBuddy }) {
                providerProfiles.append(.localCodeBuddy)
            }
            let savedProviderID = defaults.string(forKey: Self.selectedProviderIDKey).flatMap(UUID.init(uuidString:))
            selectedProviderID = providerProfiles.first(where: { $0.id == savedProviderID && $0.enabled })?.id
                ?? providerProfiles.first(where: \.enabled)?.id
            let savedPrompts = try promptsStore?.load(default: []) ?? []
            var savedBuiltIns: [String: PromptTemplate] = [:]
            for prompt in savedPrompts where prompt.builtIn { savedBuiltIns[prompt.id] = prompt }
            promptTemplates = BuiltInPrompts.all.map { builtIn in
                var merged = builtIn
                merged.enabled = savedBuiltIns[builtIn.id]?.enabled ?? builtIn.enabled
                return merged
            } + savedPrompts.filter { !$0.builtIn }
        } catch {
            lastError = L10n.userMessage(for: error)
        }
        if restoreLastProject { restoreLastProjectIfAvailable() }
    }

    func setAppLanguage(_ language: AppLanguage) {
        appLanguage = language
        defaults.set(language.rawValue, forKey: L10n.languageDefaultsKey)
        objectWillChange.send()
    }

    func selectProvider(_ id: UUID?) {
        selectedProviderID = id
        if let id { defaults.set(id.uuidString, forKey: Self.selectedProviderIDKey) }
        else { defaults.removeObject(forKey: Self.selectedProviderIDKey) }
    }

    func checkSelectedProviderAvailability() {
        guard let id = selectedProviderID else { return }
        providerHealth[id] = .checking
        Task {
            do {
                let provider = try makeSelectedProvider()
                _ = try await provider.healthCheck()
                guard selectedProviderID == id else { return }
                providerHealth[id] = .connected
            } catch {
                guard selectedProviderID == id else { return }
                providerHealth[id] = .unavailable(error.localizedDescription)
            }
        }
    }

    func toggleProjectOutline() {
        projectOutlineExpanded.toggle()
        defaults.set(projectOutlineExpanded, forKey: Self.projectOutlineExpandedKey)
    }

    func setEditorTheme(_ theme: EditorTheme) {
        editorTheme = theme
        defaults.set(theme.rawValue, forKey: Self.editorThemeKey)
    }

    func setEditorFontFamily(_ family: String) {
        editorFontFamily = family
        defaults.set(family, forKey: Self.editorFontFamilyKey)
    }

    func setEditorFontSize(_ size: Double) {
        editorFontSize = min(32, max(10, size))
        defaults.set(editorFontSize, forKey: Self.editorFontSizeKey)
    }

    func presentOpenProjectPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.openProject
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(url)
    }

    func openProject(_ root: URL) {
        do {
            try saveCurrentFileIfNeeded()
            selectedFile = nil
            selectedImageFile = nil
            sourceText = ""
            hasUnsavedChanges = false
            selectedRange = NSRange(location: 0, length: 0)
            outline = []
            pdfURL = nil
            pdfSelection = ""
            pdfPageIndex = 0
            pdfPageCount = 0
            pdfNavigationTarget = nil
            syncTeXDocument = nil
            buildLog = ""
            buildSucceeded = nil
            buildPhase = .idle
            projectRoot = root.standardizedFileURL
            projectFiles = ProjectIndexer.discoverFiles(root: root)
            projectTree = ProjectIndexer.tree(files: projectFiles)
            let support = try resolvedSupportDirectory()
            let key = String(SourceTargetService.hash(root.standardizedFileURL.path).prefix(16))
            let stateRoot = support.appendingPathComponent("Projects/\(key)", isDirectory: true)
            projectConfigStore = JSONFileStore(url: stateRoot.appendingPathComponent("configuration.json"))
            historyStore = JSONFileStore(url: stateRoot.appendingPathComponent("ai-history.json"))
            chatStore = JSONFileStore(url: stateRoot.appendingPathComponent("messages.json"))
            configuration = try projectConfigStore?.load(default: ProjectConfiguration()) ?? ProjectConfiguration()
            layout = configuration.layout
            contextScope = configuration.defaultContextScope
            history = try historyStore?.load(default: []) ?? []
            messages = configuration.privateChatMode ? [] : (try chatStore?.load(default: []) ?? [])

            let lastFileKey = "SourceLeaf.lastFile.\(key)"
            let lastFile = defaults.string(forKey: lastFileKey)
                .flatMap { path in projectFiles.first { $0.relativePath == path } }
            let configuredRootFile = configuration.rootDocument.flatMap { path in
                projectFiles.first { $0.relativePath == path && $0.kind == .tex }
            }
            let detectedRootFile = ProjectIndexer.detectRootDocument(files: projectFiles)
            let rootDocumentFile = configuredRootFile ?? detectedRootFile
            if configuredRootFile == nil { configuration.rootDocument = detectedRootFile?.relativePath }
            let initialFile = lastFile
                ?? rootDocumentFile
                ?? projectFiles.first(where: { [.tex, .bibliography, .style].contains($0.kind) })
                ?? projectFiles.first
            if let initialFile { openFile(initialFile) }
            refreshProjectOutline()
            persistConfiguration()
            defaults.set(root.standardizedFileURL.path, forKey: Self.lastProjectPathKey)
            statusText = root.lastPathComponent
            restoreCachedBuild(projectRoot: root.standardizedFileURL, rootDocument: configuration.rootDocument)
        } catch {
            report(error)
        }
    }

    private func restoreCachedBuild(projectRoot: URL, rootDocument: String?) {
        guard let rootDocument else { return }
        Task { [weak self] in
            guard let self,
                  let result = try? await compiler.cachedSuccessfulBuild(
                    projectRoot: projectRoot,
                    rootDocument: rootDocument
                  ),
                  self.projectRoot == projectRoot else { return }
            pdfURL = result.pdfURL
            buildLog = result.log
            buildSucceeded = true
            buildPhase = .finished
            if let syncTeXURL = result.syncTeXURL {
                syncTeXDocument = try? await SyncTeXDocument.load(from: syncTeXURL)
            }
            statusText = L10n.text("status.cachedPDFRestored")
        }
    }

    func openFile(_ file: ProjectFile) {
        if file.kind == .image {
            openImage(file)
            return
        }
        do {
            try saveCurrentFileIfNeeded()
            let text = try String(contentsOf: file.url, encoding: .utf8)
            suppressTextChange = true
            selectedFile = file
            sourceText = text
            hasUnsavedChanges = false
            selectedRange = NSRange(location: 0, length: 0)
            refreshActiveFileOutline()
            suppressTextChange = false
            updateLayout { layout in
                layout.show(.source, in: .center)
                if let zone = layout.zone(containing: .source) { layout.selected[zone] = .source }
            }
            rememberLastOpenedFile(file)
        } catch {
            suppressTextChange = false
            report(error)
        }
    }

    func openImage(_ file: ProjectFile) {
        do {
            try saveCurrentFileIfNeeded()
            selectedImageFile = file
            updateLayout { layout in
                layout.show(.image, in: .center)
                if let zone = layout.zone(containing: .image) { layout.selected[zone] = .image }
            }
            rememberLastOpenedFile(file)
        } catch { report(error) }
    }

    func sourceChanged(_ text: String) {
        guard !suppressTextChange else { return }
        sourceText = text
        hasUnsavedChanges = canSaveCurrentFile
        refreshActiveFileOutline()
        scheduleSave()
        scheduleCompile()
    }

    func saveCurrentFileIfNeeded() throws {
        guard let selectedFile, [.tex, .bibliography, .style].contains(selectedFile.kind) else { return }
        let currentDisk = (try? String(contentsOf: selectedFile.url, encoding: .utf8)) ?? ""
        if currentDisk != sourceText {
            try Data(sourceText.utf8).write(to: selectedFile.url, options: [.atomic])
        }
        hasUnsavedChanges = false
    }

    func saveNow() {
        do {
            try saveCurrentFileIfNeeded()
            statusText = L10n.text("status.saved")
        } catch { report(error) }
    }

    func performLaTeXEdit(_ command: LaTeXEditCommand) {
        guard selectedFile?.kind == .tex else { return }
        pendingLaTeXEdit = LaTeXEditRequest(command: command)
    }

    func acknowledgeLaTeXEdit(_ id: UUID) {
        guard pendingLaTeXEdit?.id == id else { return }
        pendingLaTeXEdit = nil
    }

    func togglePanel(_ panel: WorkspacePanel) {
        if floatingPanels.contains(panel) { return }
        if layout.contains(panel) { layout.close(panel) } else { layout.show(panel) }
        configuration.layout = layout
        persistConfiguration()
    }

    func activatePanel(_ panel: WorkspacePanel) {
        guard !floatingPanels.contains(panel) else { return }
        if let zone = layout.zone(containing: panel) {
            if layout.selected[zone] == panel { layout.close(panel) }
            else { layout.selected[zone] = panel }
        } else {
            layout.show(panel)
        }
        configuration.layout = layout
        persistConfiguration()
    }

    func revealPanel(_ panel: WorkspacePanel, in preferredZone: DockZone? = nil) {
        guard !floatingPanels.contains(panel) else { return }
        updateLayout { layout in
            if let zone = layout.zone(containing: panel) { layout.selected[zone] = panel }
            else { layout.show(panel, in: preferredZone) }
        }
    }

    func detachPanel(_ panel: WorkspacePanel) {
        floatingOrigins[panel] = layout.zone(containing: panel) ?? DockLayout.defaultZone(for: panel)
        floatingPanels.insert(panel)
        layout.close(panel)
        configuration.layout = layout
        persistConfiguration()
    }

    func restoreFloatingPanel(_ panel: WorkspacePanel) {
        guard floatingPanels.remove(panel) != nil else { return }
        layout.restore(panel, to: floatingOrigins.removeValue(forKey: panel))
        configuration.layout = layout
        persistConfiguration()
    }

    func jumpToOutline(_ item: DocumentOutlineItem) {
        if let relativePath = item.relativePath,
           selectedFile?.relativePath != relativePath,
           let file = projectFiles.first(where: { $0.relativePath == relativePath }) {
            openFile(file)
        }
        let location = SourceLineMap.utf16Location(in: sourceText, line: item.line)
        selectedRange = NSRange(location: location, length: 0)
        revealPanel(.source, in: .center)
    }

    func locateSourceInPDF() {
        guard let selectedFile,
              let syncTeXDocument,
              let location = syncTeXDocument.pdfLocation(
                sourceURL: selectedFile.url,
                line: SourceLineMap.lineNumber(in: sourceText, utf16Location: selectedRange.location)
              ) else {
            statusText = L10n.text("synctex.unavailable")
            return
        }
        pdfNavigationTarget = PDFNavigationTarget(
            pageIndex: location.pageIndex,
            x: location.x,
            yFromTop: location.yFromTop
        )
        pdfPageIndex = location.pageIndex
        revealPanel(.pdf, in: .trailing)
        statusText = L10n.text("synctex.pdfLocated")
    }

    func locatePDFPointInSource(pageIndex: Int, x: Double, yFromTop: Double, selectedText: String? = nil) {
        guard let root = projectRoot,
              let location = syncTeXDocument?.sourceLocation(
                pageIndex: pageIndex,
                x: x,
                yFromTop: yFromTop
              ),
              location.sourceURL.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/"),
              let file = projectFiles.first(where: {
                $0.url.standardizedFileURL == location.sourceURL.standardizedFileURL
              }) else {
            statusText = L10n.text("synctex.unavailable")
            return
        }
        openFile(file)
        let word = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedRange = word.flatMap {
            SourceLineMap.utf16Range(of: $0, in: sourceText, line: location.line)
        } ?? NSRange(
            location: SourceLineMap.utf16Location(in: sourceText, line: location.line),
            length: 0
        )
        revealPanel(.source, in: .center)
        statusText = String(format: L10n.text("synctex.sourceLocated"), file.relativePath, location.line)
    }

    func movePanel(_ panel: WorkspacePanel, to zone: DockZone) {
        updateLayout { $0.move(panel, to: zone) }
    }

    func closePanel(_ panel: WorkspacePanel) {
        updateLayout { $0.close(panel) }
    }

    func selectPanel(_ panel: WorkspacePanel, in zone: DockZone) {
        guard layout.zones[zone]?.contains(panel) == true else { return }
        updateLayout { $0.selected[zone] = panel }
    }

    func attachCurrentSelection() {
        guard let selectedFile, selectedRange.length > 0 else { return }
        do {
            let target = try SourceTargetService.target(
                in: sourceText,
                relativePath: selectedFile.relativePath,
                utf16Range: selectedRange
            )
            if !editTargets.contains(where: { $0.contentHash == target.contentHash && $0.relativePath == target.relativePath }) {
                editTargets.append(target)
            }
            layout.show(.codex, in: .trailing)
            configuration.layout = layout
        } catch { report(error) }
    }

    func attachLineReferencesFromInstruction() {
        guard let root = projectRoot, let active = selectedFile else { return }
        for reference in SourceTargetService.parseLineReferences(in: instruction) {
            let path = reference.relativePath ?? active.relativePath
            do {
                let url = try SourceTargetService.validatedURL(relativePath: path, projectRoot: root)
                let text = try String(contentsOf: url, encoding: .utf8)
                let target = try SourceTargetService.target(
                    in: text,
                    relativePath: path,
                    startLine: reference.startLine,
                    endLine: reference.endLine
                )
                if !editTargets.contains(where: { $0.relativePath == target.relativePath && $0.startLine == target.startLine && $0.endLine == target.endLine }) {
                    editTargets.append(target)
                }
            } catch { report(error) }
        }
    }

    func removeTarget(_ target: SourceTarget) {
        editTargets.removeAll { $0.id == target.id }
    }

    func usePrompt(_ template: PromptTemplate) {
        selectedPromptID = template.id
        let rendered = BuiltInPrompts.render(
            template,
            language: appLanguage.isChinese ? "zh" : "en",
            variables: ["user_goal": instruction]
        )
        instruction = rendered
    }

    func sendToAI() {
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let root = projectRoot else { return }
        attachLineReferencesFromInstruction()
        configuration.defaultContextScope = contextScope
        persistConfiguration()
        let userInstruction = instruction
        let targets = editTargets
        messages.append(ChatMessage(role: .user, text: userInstruction))
        persistMessages()
        generating = true
        pendingProposal = nil
        proposalValidation = [:]
        instruction = ""

        Task {
            do {
                let provider = try makeSelectedProvider()
                let context = try buildContext(scope: contextScope, targets: targets)
                let request = AIRequest(
                    instruction: userInstruction,
                    targets: targets,
                    context: context,
                    projectRoot: root
                )
                let proposal = try await provider.generateProposal(for: request)
                guard Set(proposal.replacements.map(\.targetID)).isSubset(of: Set(targets.map(\.id))) else {
                    throw AppPresentationError.unknownProposalTarget
                }
                pendingProposal = proposal
                for replacement in proposal.replacements {
                    if let target = targets.first(where: { $0.id == replacement.targetID }) {
                        proposalValidation[replacement.id] = LaTeXValidator.validate(
                            original: target.originalText,
                            replacement: replacement.replacement
                        )
                    }
                }
                messages.append(ChatMessage(role: .assistant, text: proposal.summary))
                persistMessages()
            } catch {
                report(error)
                messages.append(ChatMessage(role: .assistant, text: L10n.userMessage(for: error)))
            }
            generating = false
        }
    }

    func accept(_ replacement: ProposedReplacement) {
        guard let root = projectRoot,
              let proposal = pendingProposal,
              let target = editTargets.first(where: { $0.id == replacement.targetID }) else { return }
        do {
            let url = try SourceTargetService.validatedURL(relativePath: target.relativePath, projectRoot: root)
            let current = try String(contentsOf: url, encoding: .utf8)
            let updated = try SourceTargetService.apply(
                proposal: replacement,
                targets: editTargets,
                currentText: current
            )
            try Data(updated.utf8).write(to: url, options: [.atomic])
            history.insert(AIEditHistoryEntry(
                projectPath: root.path,
                relativePath: target.relativePath,
                originalText: target.originalText,
                replacementText: replacement.replacement,
                instruction: messages.last(where: { $0.role == .user })?.text ?? "",
                providerName: proposal.providerName
            ), at: 0)
            try historyStore?.save(history)
            if selectedFile?.relativePath == target.relativePath {
                suppressTextChange = true
                sourceText = updated
                hasUnsavedChanges = false
                outline = ProjectIndexer.outline(for: updated)
                suppressTextChange = false
            }
            editTargets.removeAll { $0.id == target.id }
            pendingProposal?.replacements.removeAll { $0.id == replacement.id }
            if pendingProposal?.replacements.isEmpty == true { pendingProposal = nil }
            if configuration.build.autoBuild { compile() }
        } catch { report(error) }
    }

    func validateAndAccept(_ replacement: ProposedReplacement) {
        guard configuration.build.trialCompileBeforeAccept else {
            accept(replacement)
            return
        }
        guard proposalValidation[replacement.id]?.hasErrors != true else {
            report(AppPresentationError.staticValidationFailed)
            return
        }
        guard let root = projectRoot,
              let rootDocument = configuration.rootDocument,
              let target = editTargets.first(where: { $0.id == replacement.targetID }) else { return }
        validatingReplacementID = replacement.id
        Task {
            do {
                let url = try SourceTargetService.validatedURL(relativePath: target.relativePath, projectRoot: root)
                let current = try String(contentsOf: url, encoding: .utf8)
                let candidate = try SourceTargetService.apply(
                    proposal: replacement,
                    targets: editTargets,
                    currentText: current
                )
                let managed = managedTectonicURL()
                let result = try await compiler.trialBuild(
                    projectRoot: root,
                    rootDocument: rootDocument,
                    editedRelativePath: target.relativePath,
                    editedText: candidate,
                    configuration: configuration.build,
                    managedTectonicURL: managed,
                    onOutput: { [weak self] chunk in
                        Task { @MainActor [weak self] in self?.receiveBuildOutput(chunk) }
                    }
                )
                buildLog = result.log
                guard result.status == .succeeded else {
                    buildSucceeded = false
                    layout.show(.buildLog, in: .bottom)
                    throw AppPresentationError.candidateCompilationFailed
                }
                accept(replacement)
            } catch { report(error) }
            validatingReplacementID = nil
        }
    }

    func reject(_ replacement: ProposedReplacement) {
        pendingProposal?.replacements.removeAll { $0.id == replacement.id }
        if pendingProposal?.replacements.isEmpty == true { pendingProposal = nil }
    }

    func compile() {
        guard let root = projectRoot,
              let rootDocument = configuration.rootDocument else {
            report(CompilerError.rootDocumentMissing)
            return
        }
        compileDebounceTask?.cancel()
        activeCompileTask?.cancel()
        buildRunning = true
        buildSucceeded = nil
        buildLog = ""
        buildPhase = .idle
        layout.show(.pdf, in: .trailing)
        activeCompileTask = Task {
            defer { buildRunning = false }
            do {
                try saveCurrentFileIfNeeded()
                let managed = managedTectonicURL()
                let result = try await compiler.build(
                    projectRoot: root,
                    rootDocument: rootDocument,
                    configuration: configuration.build,
                    managedTectonicURL: managed,
                    onOutput: { [weak self] chunk in
                        Task { @MainActor [weak self] in self?.receiveBuildOutput(chunk) }
                    }
                )
                if Task.isCancelled { return }
                buildLog = result.log
                buildPhase = result.status == .succeeded ? .finished : BuildLogSummary(log: result.log).phase
                buildSucceeded = result.status == .succeeded
                if result.status == .succeeded {
                    if let pdfURL = result.pdfURL { self.pdfURL = pdfURL }
                    if let syncTeXURL = result.syncTeXURL {
                        syncTeXDocument = try? await SyncTeXDocument.load(from: syncTeXURL)
                    } else {
                        syncTeXDocument = nil
                    }
                }
                statusText = result.status == .succeeded
                    ? L10n.text(result.reusedOutput ? "status.buildUpToDate" : "status.buildSucceeded")
                    : L10n.text("status.buildFailed")
            } catch is CancellationError {
                buildPhase = .idle
                statusText = L10n.text("status.buildCancelled")
                return
            } catch {
                buildSucceeded = false
                buildLog += "\n" + L10n.userMessage(for: error)
                report(error)
            }
        }
    }

    func cancelCompile() {
        activeCompileTask?.cancel()
        activeCompileTask = nil
        buildRunning = false
        buildPhase = .idle
        statusText = L10n.text("status.buildCancelled")
        Task { await compiler.cancel() }
    }

    func persistConfiguration() {
        configuration.layout = layout
        do { try projectConfigStore?.save(configuration) } catch { report(error) }
    }

    private func managedTectonicURL() -> URL? {
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif
        return ManagedTectonicLocator.resolve(
            bundleResourceURL: Bundle.main.resourceURL,
            supportDirectory: try? resolvedSupportDirectory(),
            architecture: architecture
        )
    }

    func saveProviderProfiles() {
        do { try profilesStore?.save(providerProfiles) } catch { report(error) }
    }

    func addPrompt() -> PromptTemplate {
        let prompt = PromptTemplate(
            id: "user.\(UUID().uuidString.lowercased())",
            name: "New Prompt",
            nameZH: "新提示词",
            body: "Describe how the selected LaTeX should be revised.",
            bodyZH: "说明应如何修改选中的 LaTeX 内容。",
            variables: ["selected_text", "section_context", "user_goal"],
            builtIn: false
        )
        promptTemplates.append(prompt)
        savePromptTemplates()
        return prompt
    }

    func duplicatePrompt(_ source: PromptTemplate) -> PromptTemplate {
        let prompt = PromptTemplate(
            id: "user.\(UUID().uuidString.lowercased())",
            name: source.name + " Copy",
            nameZH: source.nameZH + "（副本）",
            body: source.body,
            bodyZH: source.bodyZH,
            variables: source.variables,
            builtIn: false,
            enabled: true
        )
        promptTemplates.append(prompt)
        savePromptTemplates()
        return prompt
    }

    func deletePrompt(_ prompt: PromptTemplate) {
        guard !prompt.builtIn else { return }
        promptTemplates.removeAll { $0.id == prompt.id }
        savePromptTemplates()
    }

    func savePromptTemplates() {
        do { try promptsStore?.save(promptTemplates) } catch { report(error) }
    }

    func setSecret(_ secret: String, for profile: ProviderProfile) {
        do { try keychain.set(secret, account: profile.id.uuidString) } catch { report(error) }
    }

    func secret(for profile: ProviderProfile) -> String {
        (try? keychain.get(account: profile.id.uuidString)) ?? ""
    }

    func clearBuildCache() {
        do { try CacheCleaner.clearBuildCache(); statusText = L10n.text("status.cacheCleared") } catch { report(error) }
    }

    func clearChatHistory() {
        messages = []
        do { try chatStore?.remove() } catch { report(error) }
    }

    func clearAIHistory() {
        history = []
        do { try historyStore?.remove() } catch { report(error) }
    }

    func prepareRevert(_ entry: AIEditHistoryEntry) {
        guard let root = projectRoot else { return }
        do {
            guard !entry.replacementText.isEmpty else {
                throw AppPresentationError.deletedHistoryRange
            }
            let url = try SourceTargetService.validatedURL(relativePath: entry.relativePath, projectRoot: root)
            let current = try String(contentsOf: url, encoding: .utf8)
            let nsCurrent = current as NSString
            let first = nsCurrent.range(of: entry.replacementText)
            guard first.location != NSNotFound else { throw SourceTargetError.staleTarget }
            let searchStart = NSMaxRange(first)
            let remainder = NSRange(location: searchStart, length: nsCurrent.length - searchStart)
            guard nsCurrent.range(of: entry.replacementText, options: [], range: remainder).location == NSNotFound else {
                throw AppPresentationError.ambiguousHistoryRange
            }
            let target = try SourceTargetService.target(
                in: current,
                relativePath: entry.relativePath,
                utf16Range: first
            )
            let replacement = ProposedReplacement(
                targetID: target.id,
                replacement: entry.originalText,
                explanation: L10n.text("history.restoreExplanation")
            )
            editTargets = [target]
            pendingProposal = AIProposal(
                summary: L10n.text("history.restoreSummary"),
                replacements: [replacement],
                providerName: L10n.text("history.providerName")
            )
            proposalValidation = [replacement.id: LaTeXValidator.validate(
                original: target.originalText,
                replacement: replacement.replacement
            )]
            layout.show(.codex, in: .trailing)
            configuration.layout = layout
            persistConfiguration()
        } catch { report(error) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard configuration.autoSave else { return }
        let delay = configuration.autoSaveDelaySeconds
        saveTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func refreshProjectOutline() {
        let rootDocument = configuration.rootDocument
        let textFiles = projectFiles.filter { $0.kind == .tex }.sorted { lhs, rhs in
            if lhs.relativePath == rootDocument { return true }
            if rhs.relativePath == rootDocument { return false }
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
        outline = textFiles.flatMap { file in
            let source: String?
            if selectedFile?.relativePath == file.relativePath {
                source = sourceText
            } else {
                source = try? String(contentsOf: file.url, encoding: .utf8)
            }
            return ProjectIndexer.outline(
                for: source ?? "",
                relativePath: file.relativePath
            )
        }
    }

    private func refreshActiveFileOutline() {
        guard let selectedFile, selectedFile.kind == .tex else { return }
        let updated = ProjectIndexer.outline(
            for: sourceText,
            relativePath: selectedFile.relativePath
        )
        let grouped = Dictionary(grouping: outline.filter { $0.relativePath != selectedFile.relativePath }) {
            $0.relativePath ?? ""
        }
        let rootDocument = configuration.rootDocument
        let orderedPaths = projectFiles.filter { $0.kind == .tex }.map(\.relativePath).sorted { lhs, rhs in
            if lhs == rootDocument { return true }
            if rhs == rootDocument { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        outline = orderedPaths.flatMap { path in
            path == selectedFile.relativePath ? updated : (grouped[path] ?? [])
        }
    }

    private func receiveBuildOutput(_ chunk: String) {
        buildLog += chunk
        buildPhase = BuildLogSummary(log: buildLog).phase
        statusText = L10n.buildPhase(buildPhase)
    }

    private func restoreLastProjectIfAvailable() {
        guard let path = defaults.string(forKey: Self.lastProjectPathKey) else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            defaults.removeObject(forKey: Self.lastProjectPathKey)
            return
        }
        openProject(URL(fileURLWithPath: path, isDirectory: true))
    }

    private func rememberLastOpenedFile(_ file: ProjectFile) {
        guard let root = projectRoot else { return }
        let key = String(SourceTargetService.hash(root.standardizedFileURL.path).prefix(16))
        defaults.set(file.relativePath, forKey: "SourceLeaf.lastFile.\(key)")
    }

    private func resolvedSupportDirectory() throws -> URL {
        if let supportDirectoryOverride {
            try FileManager.default.createDirectory(at: supportDirectoryOverride, withIntermediateDirectories: true)
            return supportDirectoryOverride
        }
        return try ApplicationDirectories.supportDirectory()
    }

    private func scheduleCompile() {
        compileDebounceTask?.cancel()
        guard configuration.build.autoBuild else { return }
        let delay = configuration.build.debounceSeconds
        compileDebounceTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            compile()
        }
    }

    private func buildContext(scope: ContextScope, targets: [SourceTarget]) throws -> [String: String] {
        guard let root = projectRoot else { return [:] }
        switch scope {
        case .selection:
            return [:]
        case .nearby:
            var result: [String: String] = [:]
            for target in targets {
                let url = try SourceTargetService.validatedURL(relativePath: target.relativePath, projectRoot: root)
                let source = try String(contentsOf: url, encoding: .utf8)
                result["nearby:\(target.relativePath):\(target.startLine)"] = ProjectIndexer.nearbyContext(source: source, target: target)
            }
            return result
        case .section:
            var result: [String: String] = [:]
            for target in targets {
                let url = try SourceTargetService.validatedURL(relativePath: target.relativePath, projectRoot: root)
                let source = try String(contentsOf: url, encoding: .utf8)
                result["section:\(target.relativePath):\(target.startLine)"] = ProjectIndexer.sectionContext(source: source, containingLine: target.startLine)
            }
            return result
        case .document:
            guard let selectedFile else { return [:] }
            return ["document:\(selectedFile.relativePath)": sourceText]
        case .project:
            var result: [String: String] = [:]
            for file in projectFiles where [.tex, .bibliography, .style].contains(file.kind) {
                if let text = try? String(contentsOf: file.url, encoding: .utf8) { result[file.relativePath] = text }
            }
            return result
        case .custom:
            var result: [String: String] = [:]
            for path in customContextPaths.sorted() {
                let url = try SourceTargetService.validatedURL(relativePath: path, projectRoot: root)
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    result["custom:\(path)"] = text
                }
            }
            return result
        }
    }

    private func makeSelectedProvider() throws -> any AIProvider {
        let profile = providerProfiles.first(where: { $0.id == selectedProviderID }) ?? .localCodex
        switch profile.kind {
        case .localCodex:
            return try CodexCLIProvider(profile: profile)
        case .codeBuddy:
            return try CodeBuddyCLIProvider(profile: profile)
        case .openAI, .openAICompatible, .anthropic, .gemini, .ollama, .lmStudio:
            return HTTPAIProvider(profile: profile, apiKey: try keychain.get(account: profile.id.uuidString))
        case .customCLI:
            throw AppPresentationError.customCLIUnavailable
        }
    }

    private func persistMessages() {
        guard !configuration.privateChatMode else { return }
        do { try chatStore?.save(messages) } catch { report(error) }
    }

    private var selectedProviderProfile: ProviderProfile? {
        providerProfiles.first { $0.id == selectedProviderID }
            ?? providerProfiles.first(where: { $0.enabled })
    }

    private func updateSelectedProvider(_ update: (inout ProviderProfile) -> Void) {
        guard let id = selectedProviderID,
              let index = providerProfiles.firstIndex(where: { $0.id == id }) else { return }
        update(&providerProfiles[index])
        saveProviderProfiles()
    }

    private func updateLayout(_ update: (inout DockLayout) -> Void) {
        var next = layout
        update(&next)
        layout = next
        configuration.layout = next
        persistConfiguration()
    }

    private func report(_ error: Error) {
        let message = L10n.userMessage(for: error)
        lastError = message
        statusText = message
    }
}
