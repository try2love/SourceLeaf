import AppKit
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
    @State private var showingActivity = true

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.messages) { message in
                            ChatBubble(
                                message: message,
                                onEdit: { model.editMessage(message) },
                                onRegenerate: { model.regenerateResponse(after: message.id) }
                            ).id(message.id)
                        }
                        ForEach(acceptedEdits) { entry in
                            AcceptedDiffCard(entry: entry)
                        }
                        if let proposal = model.pendingProposal {
                            ForEach(proposal.replacements) { replacement in
                                ProposalCard(replacement: replacement)
                            }
                        }
                        if !model.streamingAssistantText.isEmpty {
                            HStack {
                                Text(model.streamingAssistantText)
                                    .textSelection(.enabled)
                                    .padding(9)
                                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                Spacer(minLength: 24)
                            }
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
                        if !model.generationEvents.isEmpty {
                            DisclosureGroup(
                                isExpanded: $showingActivity,
                                content: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(Array(model.generationEvents.enumerated()), id: \.offset) { _, event in
                                            Label(event, systemImage: "circle.fill")
                                                .sourceLeafFont(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.top, 5)
                                },
                                label: {
                                    Text(L10n.text("ai.activity"))
                                        .sourceLeafFont(.caption, weight: .semibold)
                                }
                            )
                        }
                    }
                    .padding(12)
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: model.generating) { _, generating in
                    showingActivity = generating
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
            HStack(spacing: 8) {
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
                            if session.id == model.selectedChatSessionID {
                                Label(session.title, systemImage: "checkmark")
                            } else { Text(session.title) }
                        }
                    }
                } label: {
                    Label(selectedSessionTitle, systemImage: "bubble.left.and.bubble.right")
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

                Menu {
                    ForEach(model.promptTemplates.filter(\.enabled)) { prompt in
                        Button(model.appLanguage.isChinese ? prompt.nameZH : prompt.name) {
                            model.usePrompt(prompt)
                        }
                    }
                } label: {
                    Label(L10n.text("ai.quickPrompt"), systemImage: "text.bubble")
                }
                .help(L10n.text("ai.quickPrompt"))

                providerHealthButton

                Menu {
                    ForEach(model.providerProfiles.filter(\.enabled)) { profile in
                        Button {
                            model.selectProvider(profile.id)
                        } label: {
                            if profile.id == model.selectedProviderID {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }
                } label: {
                    Label(selectedProviderName, systemImage: "terminal")
                }
                .help(String(format: L10n.text("provider.current"), selectedProviderName))

                Menu {
                    Button(L10n.text("provider.modelDefault")) { model.selectedProviderModel = "" }
                    ForEach(modelPresets, id: \.self) { candidate in
                        Button {
                            model.selectedProviderModel = candidate
                        } label: {
                            if model.selectedProviderModel == candidate {
                                Label(candidate, systemImage: "checkmark")
                            } else {
                                Text(candidate)
                            }
                        }
                    }
                    Divider()
                    Button(L10n.text("provider.customModel")) { presentCustomModelEditor() }
                } label: {
                    Label(model.selectedProviderModel.isEmpty ? L10n.text("provider.modelDefaultShort") : model.selectedProviderModel, systemImage: "slider.horizontal.3")
                }
                .help(String(format: L10n.text("provider.currentModel"), model.selectedProviderModel.isEmpty ? L10n.text("provider.modelDefaultShort") : model.selectedProviderModel))

                if [.localCodex, .openAI, .openAICompatible].contains(model.selectedProviderKind) {
                    Menu {
                        Button(L10n.text("provider.reasoningDefault")) { model.selectedReasoningEffort = nil }
                        ForEach([ModelReasoningEffort.low, .medium, .high, .xhigh]) { effort in
                            Button {
                                model.selectedReasoningEffort = effort
                            } label: {
                                if model.selectedReasoningEffort == effort {
                                    Label(L10n.text("reasoning.\(effort.rawValue)"), systemImage: "checkmark")
                                } else {
                                    Text(L10n.text("reasoning.\(effort.rawValue)"))
                                }
                            }
                        }
                    } label: {
                        Label(reasoningLabel, systemImage: "brain.head.profile")
                    }
                    .help(String(format: L10n.text("provider.currentReasoning"), reasoningLabel))
                }

                Menu {
                    ForEach(ContextScope.allCases) { scope in
                        Button {
                            model.contextScope = scope
                        } label: {
                            if scope == model.contextScope {
                                Label(L10n.context(scope), systemImage: "checkmark")
                            } else {
                                Text(L10n.context(scope))
                            }
                        }
                    }
                } label: {
                    Label(L10n.context(model.contextScope), systemImage: "doc.text.magnifyingglass")
                }
                .help(String(format: L10n.text("ai.currentContext"), L10n.context(model.contextScope)))

                if model.contextScope == .custom {
                    Menu {
                        ForEach(model.projectFiles.filter { [.tex, .bibliography, .style].contains($0.kind) }) { file in
                            Toggle(file.relativePath, isOn: Binding(
                                get: { model.customContextPaths.contains(file.relativePath) },
                                set: { enabled in
                                    if enabled { model.customContextPaths.insert(file.relativePath) }
                                    else { model.customContextPaths.remove(file.relativePath) }
                                }
                            ))
                        }
                    } label: {
                        Label("\(model.customContextPaths.count)", systemImage: "doc.badge.plus")
                    }
                    .help(L10n.text("ai.customContextFiles"))
                }
            }
            .buttonStyle(.borderless)
            compactControls
        }
        .padding(7)
        .background(.bar)
    }

    private var compactControls: some View {
        HStack(spacing: 8) {
            Menu {
                Button(L10n.text("chat.new")) { model.newChatSession() }
                Button(L10n.text("chat.rename")) {
                    renameTitle = selectedSessionTitle
                    showingRename = true
                }
                Divider()
                ForEach(model.chatSessions) { session in
                    Button {
                        model.selectChatSession(session.id)
                    } label: {
                        if session.id == model.selectedChatSessionID {
                            Label(session.title, systemImage: "checkmark")
                        } else {
                            Text(session.title)
                        }
                    }
                }
            } label: {
                Label(selectedSessionTitle, systemImage: "bubble.left.and.bubble.right")
                    .lineLimit(1)
            }
            .help(String(format: L10n.text("chat.currentSession"), selectedSessionTitle))

            Menu {
                ForEach(model.promptTemplates.filter(\.enabled)) { prompt in
                    Button(model.appLanguage.isChinese ? prompt.nameZH : prompt.name) {
                        model.usePrompt(prompt)
                    }
                }
            } label: {
                Image(systemName: "text.bubble")
            }
            .help(L10n.text("ai.quickPrompt"))

            providerHealthButton

            Menu {
                Section(L10n.text("ai.provider")) {
                    ForEach(model.providerProfiles.filter(\.enabled)) { profile in
                        Button {
                            model.selectProvider(profile.id)
                        } label: {
                            if profile.id == model.selectedProviderID {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }
                }
                Section(L10n.text("provider.model")) {
                    Button(L10n.text("provider.modelDefault")) { model.selectedProviderModel = "" }
                    ForEach(modelPresets, id: \.self) { candidate in
                        Button(candidate) { model.selectedProviderModel = candidate }
                    }
                    Button(L10n.text("provider.customModel")) { presentCustomModelEditor() }
                }
                if [.localCodex, .openAI, .openAICompatible].contains(model.selectedProviderKind) {
                    Section(L10n.text("provider.reasoning")) {
                        Button(L10n.text("provider.reasoningDefault")) { model.selectedReasoningEffort = nil }
                        ForEach([ModelReasoningEffort.low, .medium, .high, .xhigh]) { effort in
                            Button(L10n.text("reasoning.\(effort.rawValue)")) {
                                model.selectedReasoningEffort = effort
                            }
                        }
                    }
                }
                Section(L10n.text("ai.context")) {
                    ForEach(ContextScope.allCases) { scope in
                        Button(L10n.context(scope)) { model.contextScope = scope }
                    }
                }
            } label: {
                Label(L10n.text("ai.settings"), systemImage: "slider.horizontal.3")
            }
            .help(L10n.text("ai.settings"))

            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
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
                    TextEditor(text: $model.instruction)
                        .sourceLeafFont(.body)
                        .scrollContentBackground(.hidden)
                        .padding(3)
                        .onKeyPress { press in
                            guard press.key == .return else { return .ignored }
                            let shift = press.modifiers.contains(.shift)
                            let shouldSend = model.configuration.chatSendBehavior == .enter ? !shift : shift
                            guard shouldSend,
                                  !model.generating,
                                  !model.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .ignored }
                            model.sendToAI()
                            return .handled
                        }
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
                Spacer()
                Text(model.configuration.chatSendBehavior == .enter
                     ? L10n.text("chat.sendWithEnter")
                     : L10n.text("chat.sendWithShiftEnter"))
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
        model.chatSessions.first(where: { $0.id == model.selectedChatSessionID })?.title ?? L10n.text("chat.new")
    }

    private var acceptedEdits: [AIEditHistoryEntry] {
        model.history.filter { $0.sessionID == model.selectedChatSessionID }
    }

    private var reasoningLabel: String {
        model.selectedReasoningEffort
            .map { L10n.text("reasoning.\($0.rawValue)") }
            ?? L10n.text("provider.reasoningDefault")
    }

    private var modelPresets: [String] {
        switch model.selectedProviderKind {
        case .localCodex:
            ["gpt-5.3-codex-spark", "gpt-5.3-codex", "gpt-5.1-codex", "gpt-5-codex", "gpt-5.6-sol", "gpt-5.5", "gpt-5.4-mini", "gpt-5.4", "gpt-5.2"]
        default:
            model.selectedProviderModel.isEmpty ? [] : [model.selectedProviderModel]
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

private struct ChatBubble: View {
    let message: ChatMessage
    let onEdit: () -> Void
    let onRegenerate: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 24) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .textSelection(.enabled)
                    .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                    .padding(9)
                    .background(
                        message.role == .user
                            ? Color.accentColor
                            : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 7) {
                    Text(message.createdAt, format: .dateTime.month().day().hour().minute())
                        .sourceLeafFont(.caption2)
                        .foregroundStyle(.tertiary)
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
            if message.role != .user { Spacer(minLength: 24) }
        }
    }

    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
    }
}

private struct ProposalCard: View {
    @EnvironmentObject private var model: AppModel
    let replacement: ProposedReplacement

    private var target: SourceTarget? { model.editTargets.first { $0.id == replacement.targetID } }
    private var validation: LaTeXValidationResult? { model.proposalValidation[replacement.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(target.map { "\($0.relativePath):\($0.startLine)-\($0.endLine)" } ?? L10n.text("diff.untitled"), systemImage: "arrow.left.arrow.right")
                    .sourceLeafFont(.caption, design: .monospaced).bold()
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
            }
            HStack(alignment: .top, spacing: 0) {
                DiffText(title: L10n.text("diff.original"), text: target?.originalText ?? "", color: .red)
                Divider()
                DiffText(title: L10n.text("diff.proposed"), text: replacement.replacement, color: .green)
            }
            .frame(minHeight: 100, maxHeight: 260)
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
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
    }
}

private struct AcceptedDiffCard: View {
    let entry: AIEditHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(entry.relativePath, systemImage: "checkmark.circle.fill")
                    .sourceLeafFont(.caption, design: .monospaced, weight: .bold)
                    .foregroundStyle(.green)
                Spacer()
                Text(L10n.text("diff.accepted")).sourceLeafFont(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 0) {
                DiffText(title: L10n.text("diff.original"), text: entry.originalText, color: .red)
                Divider()
                DiffText(title: L10n.text("diff.proposed"), text: entry.replacementText, color: .green)
            }
            .frame(minHeight: 100, maxHeight: 260)
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.35)))
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
    }
}
