import AppKit
import Combine
import Foundation
import SourceLeafCore

@MainActor
final class AppModel: ObservableObject {
    @Published var projectRoot: URL?
    @Published var projectFiles: [ProjectFile] = []
    @Published var selectedFile: ProjectFile?
    @Published var sourceText = ""
    @Published var selectedRange = NSRange(location: 0, length: 0)
    @Published var outline: [DocumentOutlineItem] = []
    @Published var configuration = ProjectConfiguration()
    @Published var layout = DockLayout()
    @Published var pdfURL: URL?
    @Published var pdfSelection = ""
    @Published var buildLog = ""
    @Published var buildRunning = false
    @Published var buildSucceeded: Bool?
    @Published var messages: [ChatMessage] = []
    @Published var editTargets: [SourceTarget] = []
    @Published var pendingProposal: AIProposal?
    @Published var proposalValidation: [UUID: LaTeXValidationResult] = [:]
    @Published var instruction = ""
    @Published var contextScope: ContextScope = .section
    @Published var providerProfiles: [ProviderProfile] = [.localCodex]
    @Published var selectedProviderID: UUID?
    @Published var generating = false
    @Published var lastError: String?
    @Published var history: [AIEditHistoryEntry] = []
    @Published var promptTemplates: [PromptTemplate] = BuiltInPrompts.all
    @Published var selectedPromptID: String?
    @Published var statusText = ""

    private let compiler = CompilerService()
    private let keychain = KeychainStore()
    private var saveTask: Task<Void, Never>?
    private var compileDebounceTask: Task<Void, Never>?
    private var activeCompileTask: Task<Void, Never>?
    private var suppressTextChange = false
    private var projectConfigStore: JSONFileStore<ProjectConfiguration>?
    private var historyStore: JSONFileStore<[AIEditHistoryEntry]>?
    private var profilesStore: JSONFileStore<[ProviderProfile]>?
    private var chatStore: JSONFileStore<[ChatMessage]>?

    init() {
        do {
            let support = try ApplicationDirectories.supportDirectory()
            profilesStore = JSONFileStore(url: support.appendingPathComponent("settings/providers.json"))
            providerProfiles = try profilesStore?.load(default: [.localCodex]) ?? [.localCodex]
            if !providerProfiles.contains(where: { $0.kind == .localCodex }) {
                providerProfiles.insert(.localCodex, at: 0)
            }
            selectedProviderID = providerProfiles.first?.id
        } catch {
            lastError = error.localizedDescription
        }
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
            projectRoot = root.standardizedFileURL
            projectFiles = ProjectIndexer.discoverFiles(root: root)
            let support = try ApplicationDirectories.supportDirectory()
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

            let detected = configuration.rootDocument.flatMap { path in projectFiles.first { $0.relativePath == path } }
                ?? ProjectIndexer.detectRootDocument(files: projectFiles)
                ?? projectFiles.first(where: { $0.kind == .tex })
            if configuration.rootDocument == nil { configuration.rootDocument = detected?.relativePath }
            if let detected { openFile(detected) }
            persistConfiguration()
            statusText = root.lastPathComponent
        } catch {
            report(error)
        }
    }

    func openFile(_ file: ProjectFile) {
        do {
            try saveCurrentFileIfNeeded()
            let text = try String(contentsOf: file.url, encoding: .utf8)
            suppressTextChange = true
            selectedFile = file
            sourceText = text
            selectedRange = NSRange(location: 0, length: 0)
            outline = ProjectIndexer.outline(for: text)
            suppressTextChange = false
            layout.show(.source, in: .center)
            objectWillChange.send()
        } catch {
            suppressTextChange = false
            report(error)
        }
    }

    func sourceChanged(_ text: String) {
        guard !suppressTextChange else { return }
        sourceText = text
        outline = ProjectIndexer.outline(for: text)
        scheduleSave()
        scheduleCompile()
    }

    func saveCurrentFileIfNeeded() throws {
        guard let selectedFile else { return }
        let currentDisk = (try? String(contentsOf: selectedFile.url, encoding: .utf8)) ?? ""
        guard currentDisk != sourceText else { return }
        try Data(sourceText.utf8).write(to: selectedFile.url, options: [.atomic])
    }

    func saveNow() {
        do {
            try saveCurrentFileIfNeeded()
            statusText = L10n.text("status.saved")
        } catch { report(error) }
    }

    func togglePanel(_ panel: WorkspacePanel) {
        if layout.contains(panel) { layout.close(panel) } else { layout.show(panel) }
        configuration.layout = layout
        persistConfiguration()
    }

    func movePanel(_ panel: WorkspacePanel, to zone: DockZone) {
        layout.move(panel, to: zone)
        configuration.layout = layout
        persistConfiguration()
    }

    func closePanel(_ panel: WorkspacePanel) {
        layout.close(panel)
        configuration.layout = layout
        persistConfiguration()
    }

    func selectPanel(_ panel: WorkspacePanel, in zone: DockZone) {
        layout.selected[zone] = panel
        configuration.layout = layout
        persistConfiguration()
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
            language: Locale.current.language.languageCode?.identifier ?? "en",
            variables: ["user_goal": instruction]
        )
        instruction = rendered
    }

    func sendToAI() {
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let root = projectRoot else { return }
        attachLineReferencesFromInstruction()
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
                    throw AIProviderError.invalidResponse("The provider returned an unknown target ID.")
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
                messages.append(ChatMessage(role: .assistant, text: error.localizedDescription))
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
                outline = ProjectIndexer.outline(for: updated)
                suppressTextChange = false
            }
            editTargets.removeAll { $0.id == target.id }
            pendingProposal?.replacements.removeAll { $0.id == replacement.id }
            if pendingProposal?.replacements.isEmpty == true { pendingProposal = nil }
            if configuration.build.autoBuild { compile() }
        } catch { report(error) }
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
        layout.show(.pdf, in: .trailing)
        activeCompileTask = Task {
            do {
                try saveCurrentFileIfNeeded()
                let managed = try? ApplicationDirectories.supportDirectory().appendingPathComponent("Engines/tectonic")
                let result = try await compiler.build(
                    projectRoot: root,
                    rootDocument: rootDocument,
                    configuration: configuration.build,
                    managedTectonicURL: managed
                )
                if Task.isCancelled { return }
                buildLog = result.log
                buildSucceeded = result.status == .succeeded
                if let pdfURL = result.pdfURL { self.pdfURL = pdfURL }
                statusText = result.status == .succeeded ? L10n.text("status.buildSucceeded") : L10n.text("status.buildFailed")
            } catch is CancellationError {
                return
            } catch {
                buildSucceeded = false
                buildLog += "\n" + error.localizedDescription
                report(error)
            }
            buildRunning = false
        }
    }

    func persistConfiguration() {
        configuration.layout = layout
        do { try projectConfigStore?.save(configuration) } catch { report(error) }
    }

    func saveProviderProfiles() {
        do { try profilesStore?.save(providerProfiles) } catch { report(error) }
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
            return [:]
        }
    }

    private func makeSelectedProvider() throws -> any AIProvider {
        let profile = providerProfiles.first(where: { $0.id == selectedProviderID }) ?? .localCodex
        switch profile.kind {
        case .localCodex:
            return try CodexCLIProvider()
        case .openAI, .openAICompatible, .anthropic, .gemini, .ollama, .lmStudio:
            return HTTPAIProvider(profile: profile, apiKey: try keychain.get(account: profile.id.uuidString))
        case .customCLI:
            throw AIProviderError.invalidResponse("Custom CLI profiles will be available after a command passes the local safety check.")
        }
    }

    private func persistMessages() {
        guard !configuration.privateChatMode else { return }
        do { try chatStore?.save(messages) } catch { report(error) }
    }

    private func report(_ error: Error) {
        lastError = error.localizedDescription
        statusText = error.localizedDescription
    }
}
