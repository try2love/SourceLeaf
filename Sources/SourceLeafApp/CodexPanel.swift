import AppKit
import Carbon.HIToolbox
import SwiftUI
import SourceLeafCore

struct CodexPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("SourceLeaf.composerHeight") private var composerHeight = 120.0
    @State private var composerDragStart: Double?
    @State private var renameTitle = ""
    @State private var showingRename = false
    @State private var customModelDraft = ""
    @State private var showingCustomModel = false

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.messages) { message in
                            chatMessageView(message)
                                .id(message.id)
                        }
                        ForEach(acceptedEdits) { entry in
                            AcceptedDiffCard(entry: entry)
                        }
                        if let proposal = model.pendingProposal {
                            ForEach(proposal.replacements) { replacement in
                                ProposalCard(replacement: replacement)
                            }
                        }
                        if !model.generationEvents.isEmpty {
                            AIActivityView(events: model.generationEvents)
                        }
                        if !model.streamingAssistantText.isEmpty {
                            HStack {
                                Text(model.streamingAssistantText)
                                    .textSelection(.enabled)
                                    .padding(9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                Spacer(minLength: 24)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        if model.generating || !model.generationStatus.isEmpty {
                            HStack {
                                if model.generating {
                                    ProgressView()
                                } else {
                                    Image(systemName: "stop.circle")
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    if model.generating {
                                        Text(L10n.text("ai.thinking"))
                                    }
                                    if !model.generationStatus.isEmpty {
                                        Text(model.generationStatus).sourceLeafFont(.caption2)
                                    }
                                }
                                Spacer()
                                if model.generating {
                                    Button(L10n.text("ai.stop")) { model.cancelAIResponse() }
                                        .buttonStyle(.bordered)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            composer
        }
        .background(colorScheme == .dark ? Color(red: 0.055, green: 0.055, blue: 0.06) : Color.white)
        .popover(isPresented: $showingCustomModel) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("provider.customModel")).sourceLeafFont(.headline, weight: .semibold)
                TextField(L10n.text("provider.customModelPlaceholder"), text: $customModelDraft)
                    .frame(width: 300)
                    .onSubmit { applyCustomModel() }
                HStack {
                    Spacer()
                    Button(L10n.text("action.cancel")) { showingCustomModel = false }
                    Button(L10n.text("action.save")) { applyCustomModel() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            fullControls
            compactControls
            iconOnlyControls
        }
        .padding(7)
        .background(.bar)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private var fullControls: some View {
        HStack(spacing: 8) {
            sessionMenu(labelStyle: .title, maxWidth: 190)
            quickPromptMenu(labelStyle: .title)
            providerHealthButton
            providerMenu(maxWidth: 130)
            modelMenu(maxWidth: 150)
            if [.localCodex, .openAI, .openAICompatible].contains(model.selectedProviderKind) {
                reasoningMenu(maxWidth: 120)
            }
            contextMenu(maxWidth: 120)
            customContextMenuIfNeeded
        }
        .buttonStyle(.borderless)
    }

    private var compactControls: some View {
        HStack(spacing: 8) {
            sessionMenu(labelStyle: .title, maxWidth: 150)
            quickPromptMenu(labelStyle: .icon)
            providerHealthButton
            combinedAISettingsMenu(labelStyle: .title)
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
    }

    private var iconOnlyControls: some View {
        HStack(spacing: 8) {
            sessionMenu(labelStyle: .icon, maxWidth: nil)
            quickPromptMenu(labelStyle: .icon)
            providerHealthButton
            combinedAISettingsMenu(labelStyle: .icon)
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
    }

    private enum ToolbarLabelStyle {
        case title
        case icon
    }

    private func sessionMenu(labelStyle: ToolbarLabelStyle, maxWidth: CGFloat?) -> some View {
        Menu {
            Button(L10n.text("chat.new")) { model.newChatSession() }
            Button(L10n.text("chat.rename")) {
                renameTitle = model.chatSessions.first(where: { $0.id == model.selectedChatSessionID })?.title ?? ""
                showingRename = true
            }
            Divider()
            ForEach(model.chatSessions) { session in
                Button {
                    model.selectChatSession(session.id)
                } label: {
                    let title = sessionDisplayTitle(session)
                    if session.id == model.selectedChatSessionID {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            toolbarLabel(
                title: selectedSessionTitle,
                systemImage: "bubble.left.and.bubble.right",
                style: labelStyle,
                maxWidth: maxWidth
            )
        }
        .help(String(format: L10n.text("chat.currentSession"), selectedSessionTitle))
        .popover(isPresented: $showingRename) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("chat.rename")).sourceLeafFont(.headline, weight: .semibold)
                TextField(L10n.text("chat.title"), text: $renameTitle)
                    .frame(width: 260)
                    .onSubmit {
                        model.renameSelectedChatSession(renameTitle)
                        showingRename = false
                    }
                HStack {
                    Spacer()
                    Button(L10n.text("action.cancel")) { showingRename = false }
                    Button(L10n.text("action.save")) {
                        model.renameSelectedChatSession(renameTitle)
                        showingRename = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
        }
    }

    private func quickPromptMenu(labelStyle: ToolbarLabelStyle) -> some View {
        Menu {
            ForEach(model.promptTemplates.filter(\.enabled)) { prompt in
                Button(model.appLanguage.isChinese ? prompt.nameZH : prompt.name) {
                    model.usePrompt(prompt)
                }
            }
        } label: {
            toolbarLabel(
                title: L10n.text("ai.quickPrompt"),
                systemImage: "text.bubble",
                style: labelStyle,
                maxWidth: 130
            )
        }
        .help(L10n.text("ai.quickPrompt"))
    }

    private func providerMenu(maxWidth: CGFloat?) -> some View {
        Menu {
            providerMenuItems
        } label: {
            toolbarLabel(title: selectedProviderName, systemImage: "terminal", style: .title, maxWidth: maxWidth)
        }
        .help(String(format: L10n.text("provider.current"), selectedProviderName))
    }

    private func modelMenu(maxWidth: CGFloat?) -> some View {
        Menu {
            modelMenuItems
        } label: {
            toolbarLabel(title: modelMenuTitle, systemImage: "slider.horizontal.3", style: .title, maxWidth: maxWidth)
        }
        .help(String(format: L10n.text("provider.currentModel"), modelMenuTitle))
    }

    private func reasoningMenu(maxWidth: CGFloat?) -> some View {
        Menu {
            reasoningMenuItems
        } label: {
            toolbarLabel(title: reasoningLabel, systemImage: "brain.head.profile", style: .title, maxWidth: maxWidth)
        }
        .help(String(format: L10n.text("provider.currentReasoning"), reasoningLabel))
    }

    private func contextMenu(maxWidth: CGFloat?) -> some View {
        Menu {
            contextMenuItems
        } label: {
            toolbarLabel(title: L10n.context(model.contextScope), systemImage: "doc.text.magnifyingglass", style: .title, maxWidth: maxWidth)
        }
        .help(String(format: L10n.text("ai.currentContext"), L10n.context(model.contextScope)))
    }

    private func combinedAISettingsMenu(labelStyle: ToolbarLabelStyle) -> some View {
        Menu {
            Section(L10n.text("ai.provider")) { providerMenuItems }
            Section(L10n.text("provider.model")) { modelMenuItems }
            if [.localCodex, .openAI, .openAICompatible].contains(model.selectedProviderKind) {
                Section(L10n.text("provider.reasoning")) { reasoningMenuItems }
            }
            Section(L10n.text("ai.context")) { contextMenuItems }
            if model.contextScope == .custom {
                Section(L10n.text("ai.customContextFiles")) { customContextMenuItems }
            }
        } label: {
            toolbarLabel(
                title: L10n.text("ai.settings"),
                systemImage: "slider.horizontal.3",
                style: labelStyle,
                maxWidth: 120
            )
        }
        .help(model.currentAIConfigurationSummary)
    }

    @ViewBuilder
    private var providerMenuItems: some View {
        ForEach(model.providerProfiles.filter(\.enabled)) { profile in
            Button {
                model.selectProvider(profile.id)
            } label: {
                if profile.id == model.selectedProviderID {
                    selectedMenuItemLabel(profile.name)
                } else {
                    Text(profile.name)
                }
            }
        }
    }

    @ViewBuilder
    private var modelMenuItems: some View {
        Button {
            model.selectedProviderModel = ""
        } label: {
            if model.selectedProviderModel.isEmpty {
                selectedMenuItemLabel(L10n.text("provider.modelDefault"))
            } else {
                Text(L10n.text("provider.modelDefault"))
            }
        }
        ForEach(modelPresets, id: \.self) { candidate in
            Button {
                model.selectedProviderModel = candidate
            } label: {
                if model.selectedProviderModel == candidate {
                    selectedMenuItemLabel(candidate)
                } else {
                    Text(candidate)
                }
            }
        }
        Divider()
        Button(L10n.text("provider.customModel")) { presentCustomModelEditor() }
    }

    @ViewBuilder
    private var reasoningMenuItems: some View {
        Button {
            model.selectedReasoningEffort = nil
        } label: {
            if model.selectedReasoningEffort == nil {
                selectedMenuItemLabel(L10n.text("provider.reasoningDefault"))
            } else {
                Text(L10n.text("provider.reasoningDefault"))
            }
        }
        ForEach([ModelReasoningEffort.low, .medium, .high, .xhigh]) { effort in
            Button {
                model.selectedReasoningEffort = effort
            } label: {
                if model.selectedReasoningEffort == effort {
                    selectedMenuItemLabel(L10n.text("reasoning.\(effort.rawValue)"))
                } else {
                    Text(L10n.text("reasoning.\(effort.rawValue)"))
                }
            }
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        ForEach(ContextScope.allCases) { scope in
            Button {
                model.setContextScope(scope)
            } label: {
                if scope == model.contextScope {
                    selectedMenuItemLabel(L10n.context(scope))
                } else {
                    Text(L10n.context(scope))
                }
            }
        }
    }

    @ViewBuilder
    private var customContextMenuIfNeeded: some View {
        if model.contextScope == .custom {
            Menu {
                customContextMenuItems
            } label: {
                toolbarLabel(title: "\(model.customContextPaths.count)", systemImage: "doc.badge.plus", style: .title, maxWidth: 52)
            }
            .help(L10n.text("ai.customContextFiles"))
        }
    }

    @ViewBuilder
    private var customContextMenuItems: some View {
        ForEach(model.projectFiles.filter { [.tex, .bibliography, .style].contains($0.kind) }) { file in
            Toggle(file.relativePath, isOn: Binding(
                get: { model.customContextPaths.contains(file.relativePath) },
                set: { enabled in
                    if enabled { model.customContextPaths.insert(file.relativePath) }
                    else { model.customContextPaths.remove(file.relativePath) }
                }
            ))
        }
    }

    @ViewBuilder
    private func toolbarLabel(title: String, systemImage: String, style: ToolbarLabelStyle, maxWidth: CGFloat?) -> some View {
        switch style {
        case .title:
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: maxWidth, alignment: .leading)
        case .icon:
            Image(systemName: systemImage)
                .accessibilityLabel(title)
        }
    }

    private func selectedMenuItemLabel(_ title: String) -> some View {
        Label(title, systemImage: "circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.green, .primary)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.and.down")
                Text(L10n.text("ai.resizeComposer"))
            }
                .sourceLeafFont(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 18)
                .contentShape(Rectangle())
                .help(L10n.text("ai.resizeComposerHelp"))
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if composerDragStart == nil { composerDragStart = composerHeight }
                            composerHeight = max(64, (composerDragStart ?? composerHeight) - value.translation.height)
                        }
                        .onEnded { _ in composerDragStart = nil }
                )
            if !model.editTargets.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(model.editTargets) { target in
                            HStack(spacing: 4) {
                                Text("\(target.relativePath):\(target.startLine)-\(target.endLine)")
                                    .sourceLeafFont(.caption, design: .monospaced)
                                Button { model.removeTarget(target) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    ChatComposerTextView(
                        text: $model.instruction,
                        sendBehavior: model.configuration.chatSendBehavior,
                        isGenerating: model.generating,
                        onSend: { model.sendToAI() }
                    )
                    .padding(3)
                    if model.instruction.isEmpty {
                        Text(L10n.text("ai.composerPlaceholder"))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: composerHeight)
                .background(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.25)))
                Button {
                    if model.generating { model.cancelAIResponse() }
                    else { model.sendToAI() }
                } label: {
                    Image(systemName: model.generating ? "stop.circle.fill" : "arrow.up.circle.fill").sourceLeafFont(.title2)
                }
                .buttonStyle(.plain)
                .disabled(!model.generating && model.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(model.generating ? L10n.text("ai.stop") : L10n.text("ai.send"))
            }
            HStack {
                Text(model.editTargets.isEmpty ? L10n.text("ai.chatOnlyHint") : L10n.text("ai.targetHint"))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(model.configuration.chatSendBehavior == .enter
                     ? L10n.text("chat.sendWithEnter")
                     : L10n.text("chat.sendWithShiftEnter"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .sourceLeafFont(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(9)
    }

    @ViewBuilder
    private var providerHealthButton: some View {
        switch model.selectedProviderHealth {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
                .help(L10n.text("provider.healthChecking"))
        case .connected:
            Button { model.checkSelectedProviderAvailability() } label: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .help(L10n.text("provider.healthConnected"))
        case let .unavailable(message):
            Button { model.checkSelectedProviderAvailability() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
            .help(L10n.text("provider.healthUnavailable") + "\n" + message)
        case .unknown:
            Button { model.checkSelectedProviderAvailability() } label: {
                Label(L10n.text("provider.healthUnknown"), systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .sourceLeafFont(.caption)
            }
            .help(L10n.text("provider.healthCheck"))
        }
    }

    private var selectedProviderName: String {
        model.providerProfiles.first { $0.id == model.selectedProviderID }?.name ?? L10n.text("ai.provider")
    }

    private var selectedSessionTitle: String {
        guard let session = model.chatSessions.first(where: { $0.id == model.selectedChatSessionID }) else {
            return L10n.text("chat.new")
        }
        return sessionDisplayTitle(session)
    }

    private var acceptedEdits: [AIEditHistoryEntry] {
        model.history.filter { $0.sessionID == model.selectedChatSessionID }
    }

    private var reasoningLabel: String {
        model.selectedReasoningEffort
            .map { L10n.text("reasoning.\($0.rawValue)") }
            ?? L10n.text("provider.reasoningDefault")
    }

    private var modelMenuTitle: String {
        model.selectedProviderModel.isEmpty
            ? L10n.text("provider.modelDefaultShort")
            : model.selectedProviderModel
    }

    private var modelPresets: [String] {
        switch model.selectedProviderKind {
        case .localCodex:
            ["gpt-5.3-codex-spark", "gpt-5.3-codex", "gpt-5.1-codex", "gpt-5-codex", "gpt-5.6-sol", "gpt-5.5", "gpt-5.4-mini", "gpt-5.4", "gpt-5.2"]
        default:
            model.selectedProviderModel.isEmpty ? [] : [model.selectedProviderModel]
        }
    }

    private func sessionDisplayTitle(_ session: ChatSession) -> String {
        guard let index = model.chatSessions.firstIndex(where: { $0.id == session.id }) else {
            return session.title
        }
        return "#\(model.chatSessions.count - index) \(session.title)"
    }

    @ViewBuilder
    private func chatMessageView(_ message: ChatMessage) -> some View {
        if message.text.hasPrefix(AppModel.aiActivityPrefix) {
            AIActivityView(
                events: message.text.removingPrefix(AppModel.aiActivityPrefix).split(separator: "\n").map(String.init),
                initiallyExpanded: false
            )
        } else if message.text.hasPrefix(AppModel.aiConfigurationPrefix) {
            AIConfigurationNotice(summary: message.text.removingPrefix(AppModel.aiConfigurationPrefix))
        } else if message.text.hasPrefix(AppModel.aiHealthPrefix) {
            AIConfigurationNotice(summary: message.text.removingPrefix(AppModel.aiHealthPrefix))
        } else {
            ChatBubble(
                message: message,
                onEdit: { model.editMessage(message) },
                onRegenerate: { model.regenerateResponse(after: message.id) }
            )
        }
    }

    private func presentCustomModelEditor() {
        customModelDraft = model.selectedProviderModel
        showingCustomModel = true
    }

    private func applyCustomModel() {
        model.selectedProviderModel = customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        showingCustomModel = false
    }
}

struct ChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let sendBehavior: ChatSendBehavior
    let isGenerating: Bool
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        guard let textView = scrollView.documentView as? ComposerNSTextView else {
            let replacement = ComposerNSTextView()
            scrollView.documentView = replacement
            configure(replacement, context: context)
            return scrollView
        }
        configure(textView, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? ComposerNSTextView else { return }
        textView.sendBehavior = sendBehavior
        textView.isGenerating = isGenerating
        textView.onSend = {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !isGenerating, !trimmed.isEmpty else { return false }
            onSend()
            return true
        }
        if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
        }
    }

    private func configure(_ textView: ComposerNSTextView, context: Context) {
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.sendBehavior = sendBehavior
        textView.isGenerating = isGenerating
        textView.onSend = {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !isGenerating, !trimmed.isEmpty else { return false }
            onSend()
            return true
        }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatComposerTextView

        init(parent: ChatComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

final class ComposerNSTextView: NSTextView {
    var sendBehavior: ChatSendBehavior = .enter
    var isGenerating = false
    var onSend: (() -> Bool)?
    private var lastMarkedTextCommitDate = Date.distantPast
    private var lastCompositionLikeKeyDate = Date.distantPast

    override func unmarkText() {
        super.unmarkText()
        lastMarkedTextCommitDate = Date()
    }

    override func keyDown(with event: NSEvent) {
        let compositionInputSourceActive = Self.currentInputSourcePrefersReturnCommit()
        if Self.isPlainPrintableInput(event),
           compositionInputSourceActive {
            lastCompositionLikeKeyDate = Date()
        }
        if Self.shouldTreatReturnAsSend(
            characters: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags,
            sendBehavior: sendBehavior,
            hasMarkedText: hasMarkedText(),
            recentlyCommittedMarkedText: Date().timeIntervalSince(lastMarkedTextCommitDate) < 0.18,
            compositionInputSourceActive: compositionInputSourceActive,
            recentlyTypedWithCompositionInputSource: Date().timeIntervalSince(lastCompositionLikeKeyDate) < 1.2
        ), onSend?() == true {
            return
        }
        super.keyDown(with: event)
    }

    nonisolated static func shouldTreatReturnAsSend(
        characters: String?,
        modifierFlags: NSEvent.ModifierFlags,
        sendBehavior: ChatSendBehavior,
        hasMarkedText: Bool,
        recentlyCommittedMarkedText: Bool = false,
        compositionInputSourceActive: Bool = false,
        recentlyTypedWithCompositionInputSource: Bool = false
    ) -> Bool {
        guard characters == "\r" || characters == "\n" else { return false }
        guard !hasMarkedText else { return false }
        guard !recentlyCommittedMarkedText else { return false }
        let shift = modifierFlags.contains(.shift)
        if compositionInputSourceActive && !shift { return false }
        if recentlyTypedWithCompositionInputSource && !shift { return false }
        return sendBehavior == .enter ? !shift : shift
    }

    static func currentInputSourcePrefersReturnCommit() -> Bool {
        if let current = NSTextInputContext.current?.selectedKeyboardInputSource,
           inputSourcePrefersReturnCommit(sourceID: current) {
            return true
        }
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let rawID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
        let id = unsafeBitCast(rawID, to: CFString.self) as String
        let localizedName = (TISGetInputSourceProperty(source, kTISPropertyLocalizedName).map {
            unsafeBitCast($0, to: CFString.self) as String
        }) ?? ""
        let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
            .flatMap { unsafeBitCast($0, to: NSArray.self) as? [String] } ?? []
        return inputSourcePrefersReturnCommit(sourceID: id, localizedName: localizedName, languages: languages)
    }

    nonisolated static func inputSourcePrefersReturnCommit(
        sourceID id: String,
        localizedName: String = "",
        languages: [String] = []
    ) -> Bool {
        let lowered = (id + " " + localizedName).lowercased()
        if lowered.contains("pinyin")
            || lowered.contains("shuangpin")
            || lowered.contains("wubi")
            || lowered.contains("zhuyin")
            || lowered.contains("cangjie")
            || lowered.contains("scim")
            || lowered.contains("kotoeri")
            || lowered.contains("hangul")
            || lowered.contains("拼音")
            || lowered.contains("双拼")
            || lowered.contains("五笔") {
            return true
        }
        if lowered.contains("简体")
            || lowered.contains("繁体")
            || lowered.contains("中文")
            || lowered.contains("japanese")
            || lowered.contains("korean")
            || lowered.contains("chinese") {
            return true
        }
        if languages.contains(where: { language in
            let lower = language.lowercased()
            return lower.hasPrefix("zh") || lower.hasPrefix("ja") || lower.hasPrefix("ko")
        }) {
            return true
        }
        return !id.contains(".keylayout.")
    }

    private static func isPlainPrintableInput(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let characters = event.characters,
              characters.count == 1,
              let scalar = characters.unicodeScalars.first else { return false }
        return !CharacterSet.controlCharacters.contains(scalar)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let onEdit: () -> Void
    let onRegenerate: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 32) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                bubbleContent
                HStack(spacing: 7) {
                    Text(message.createdAt, format: .dateTime.month().day().hour().minute())
                        .sourceLeafFont(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Button { copyMessage() } label: { Image(systemName: "doc.on.doc") }
                        .help(L10n.text("action.copy"))
                    if message.role == .user {
                        Button(action: onEdit) { Image(systemName: "pencil") }
                            .help(L10n.text("chat.edit"))
                    } else {
                        Button(action: onRegenerate) { Image(systemName: "arrow.clockwise") }
                            .help(L10n.text("chat.regenerate"))
                    }
                }
                .buttonStyle(.borderless)
            }
            if message.role != .user { Spacer(minLength: 32) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        ViewThatFits(in: .horizontal) {
            styledBubble
                .fixedSize(horizontal: true, vertical: true)
            styledBubble
                .frame(maxWidth: 720, alignment: message.role == .user ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .layoutPriority(1)
    }

    private var styledBubble: some View {
        RenderedChatText(text: message.text)
            .textSelection(.enabled)
            .lineLimit(nil)
            .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            .padding(9)
            .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private var bubbleBackground: Color {
        message.role == .user
            ? Color.accentColor
            : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07))
    }

    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
    }
}

private struct RenderedChatText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(ChatMarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case let .heading(level, content):
                    InlineMarkdownText(content)
                        .sourceLeafFont(level == 1 ? .headline : .subheadline, weight: .semibold)
                case let .paragraph(content):
                    InlineMarkdownText(content)
                case let .bullet(content):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        InlineMarkdownText(content)
                    }
                case let .numbered(number, content):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(number).")
                        InlineMarkdownText(content)
                    }
                case let .quote(content):
                    HStack(alignment: .top, spacing: 7) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: 3)
                        InlineMarkdownText(content)
                            .foregroundStyle(.secondary)
                    }
                case let .code(content):
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(7)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}

private struct InlineMarkdownText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if let rendered = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(rendered)
        } else {
            Text(text)
        }
    }
}

private struct ChatMarkdownBlock {
    enum Kind {
        case heading(level: Int, content: String)
        case paragraph(String)
        case bullet(String)
        case numbered(number: Int, content: String)
        case quote(String)
        case code(String)
    }

    let kind: Kind

    static func parse(_ text: String) -> [ChatMarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [ChatMarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            let content = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph.removeAll()
            guard !content.isEmpty else { return }
            blocks.append(ChatMarkdownBlock(kind: .paragraph(content)))
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    blocks.append(ChatMarkdownBlock(kind: .code(codeLines.joined(separator: "\n"))))
                    codeLines.removeAll()
                    inCode = false
                } else {
                    flushParagraph()
                    inCode = true
                }
                continue
            }
            if inCode {
                codeLines.append(line)
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                flushParagraph()
                continue
            }
            if let heading = heading(in: trimmed) {
                flushParagraph()
                blocks.append(ChatMarkdownBlock(kind: .heading(level: heading.level, content: heading.content)))
            } else if let bullet = bullet(in: trimmed) {
                flushParagraph()
                blocks.append(ChatMarkdownBlock(kind: .bullet(bullet)))
            } else if let numbered = numbered(in: trimmed) {
                flushParagraph()
                blocks.append(ChatMarkdownBlock(kind: .numbered(number: numbered.number, content: numbered.content)))
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                blocks.append(ChatMarkdownBlock(kind: .quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))))
            } else {
                paragraph.append(line)
            }
        }
        if inCode {
            blocks.append(ChatMarkdownBlock(kind: .code(codeLines.joined(separator: "\n"))))
        }
        flushParagraph()
        return blocks.isEmpty ? [ChatMarkdownBlock(kind: .paragraph(text))] : blocks
    }

    private static func heading(in line: String) -> (level: Int, content: String)? {
        let marks = line.prefix { $0 == "#" }
        guard !marks.isEmpty, marks.count <= 3, line.dropFirst(marks.count).first == " " else { return nil }
        return (marks.count, String(line.dropFirst(marks.count + 1)))
    }

    private static func bullet(in line: String) -> String? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        return String(line.dropFirst(2))
    }

    private static func numbered(in line: String) -> (number: Int, content: String)? {
        var digits = ""
        for character in line {
            if character.isNumber { digits.append(character) } else { break }
        }
        guard !digits.isEmpty,
              line.dropFirst(digits.count).hasPrefix(". "),
              let number = Int(digits) else { return nil }
        return (number, String(line.dropFirst(digits.count + 2)))
    }
}

private struct AIConfigurationNotice: View {
    let summary: String

    var body: some View {
        Label(summary, systemImage: "slider.horizontal.3")
            .sourceLeafFont(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .help(summary)
    }
}

private struct AIActivityView: View {
    let events: [String]
    @State private var expanded: Bool

    init(events: [String], initiallyExpanded: Bool = true) {
        self.events = events
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: "circle.fill")
                            .sourceLeafFont(.caption2)
                            .foregroundStyle(.green)
                        Text(event)
                            .sourceLeafFont(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 5)
        } label: {
            Label(L10n.text("ai.activity"), systemImage: "circle.fill")
                .sourceLeafFont(.caption, weight: .semibold)
                .foregroundStyle(.green)
        }
        .help(L10n.text("ai.activity"))
    }
}

private struct ProposalCard: View {
    @EnvironmentObject private var model: AppModel
    let replacement: ProposedReplacement

    private var target: SourceTarget? { model.editTargets.first { $0.id == replacement.targetID } }
    private var validation: LaTeXValidationResult? { model.proposalValidation[replacement.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Label(target.map { "\($0.relativePath):\($0.startLine)-\($0.endLine)" } ?? L10n.text("diff.untitled"), systemImage: "arrow.left.arrow.right")
                    .sourceLeafFont(.caption, design: .monospaced).bold()
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if validation?.hasErrors == true {
                    Label(L10n.text("validation.error"), systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                } else if validation?.issues.isEmpty == false {
                    Label(L10n.text("validation.warning"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else {
                    Label(L10n.text("validation.clean"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            if !replacement.explanation.isEmpty {
                Text(replacement.explanation).sourceLeafFont(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AdaptiveDiffPair(
                original: target?.originalText ?? "",
                proposed: replacement.replacement
            )
            if let validation, !validation.issues.isEmpty {
                ForEach(validation.issues) { issue in
                    Label(L10n.validationMessage(issue), systemImage: issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                        .sourceLeafFont(.caption)
                        .foregroundStyle(issue.severity == .error ? .red : .orange)
                }
            }
            HStack {
                Button(L10n.text("action.reject"), role: .destructive) { model.reject(replacement) }
                Spacer()
                Button(L10n.text("action.adjust")) {
                    model.instruction = String(
                        format: L10n.text("ai.adjustInstruction"),
                        target?.relativePath ?? L10n.text("ai.attachedTarget")
                    )
                }
                Menu {
                    Button(L10n.text("action.forceAccept")) { model.accept(replacement) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button {
                    model.validateAndAccept(replacement)
                } label: {
                    if model.validatingReplacementID == replacement.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(model.configuration.build.trialCompileBeforeAccept ? L10n.text("action.validateAccept") : L10n.text("action.accept"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.validatingReplacementID != nil)
            }
            .lineLimit(1)
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    var looksLikeMarkdown: Bool {
        contains("**")
            || contains("__")
            || contains("`")
            || contains("[")
            || contains("](")
            || range(of: #"(?m)^\s{0,3}([-*+]|\d+\.)\s+"#, options: .regularExpression) != nil
            || range(of: #"(?m)^\s{0,3}#{1,6}\s+"#, options: .regularExpression) != nil
    }
}

private struct AcceptedDiffCard: View {
    let entry: AIEditHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(entry.relativePath, systemImage: "checkmark.circle.fill")
                    .sourceLeafFont(.caption, design: .monospaced, weight: .bold)
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(L10n.text("diff.accepted")).sourceLeafFont(.caption).foregroundStyle(.secondary)
            }
            AdaptiveDiffPair(original: entry.originalText, proposed: entry.replacementText)
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.35)))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AdaptiveDiffPair: View {
    let original: String
    let proposed: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                DiffText(title: L10n.text("diff.original"), text: original, color: .red)
                Divider()
                DiffText(title: L10n.text("diff.proposed"), text: proposed, color: .green)
            }
            VStack(alignment: .leading, spacing: 8) {
                DiffText(title: L10n.text("diff.original"), text: original, color: .red)
                DiffText(title: L10n.text("diff.proposed"), text: proposed, color: .green)
            }
        }
        .frame(minHeight: 100, maxHeight: 300)
    }
}

private struct DiffText: View {
    let title: String
    let text: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).sourceLeafFont(.caption, weight: .bold).foregroundStyle(color)
            ScrollView(.vertical) {
                Text(text)
                    .sourceLeafFont(.body, design: .monospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(color.opacity(0.05))
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
