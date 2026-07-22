import AppKit
import SwiftUI
import SourceLeafCore

struct CodexPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("SourceLeaf.composerHeight") private var composerHeight = 120.0
    @State private var composerDragStart: Double?

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.messages) { message in
                            ChatBubble(message: message).id(message.id)
                        }
                        if let proposal = model.pendingProposal {
                            ForEach(proposal.replacements) { replacement in
                                ProposalCard(replacement: replacement)
                            }
                        }
                        if model.generating {
                            HStack { ProgressView(); Text(L10n.text("ai.thinking")) }
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
    }

    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(model.promptTemplates.filter(\.enabled)) { prompt in
                        Button(model.appLanguage.isChinese ? prompt.nameZH : prompt.name) {
                            model.usePrompt(prompt)
                        }
                    }
                } label: {
                    Label(L10n.text("ai.quickPrompt"), systemImage: "text.bubble")
                }

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
                } label: {
                    Label(model.selectedProviderModel.isEmpty ? L10n.text("provider.modelDefaultShort") : model.selectedProviderModel, systemImage: "slider.horizontal.3")
                }

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
        }
        .padding(7)
        .background(.bar)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 44, height: 4)
                .frame(maxWidth: .infinity, minHeight: 7)
                .contentShape(Rectangle())
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
                                    .font(.caption.monospaced())
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
                        .font(.body)
                        .scrollContentBackground(.hidden)
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
                Button { model.sendToAI() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(model.generating || model.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            Text(model.editTargets.isEmpty ? L10n.text("ai.chatOnlyHint") : L10n.text("ai.targetHint"))
                .font(.caption2)
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
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
            .help(L10n.text("provider.healthCheck"))
        }
    }

    private var selectedProviderName: String {
        model.providerProfiles.first { $0.id == model.selectedProviderID }?.name ?? L10n.text("ai.provider")
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
}

private struct ChatBubble: View {
    let message: ChatMessage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 24) }
            Text(message.text)
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .padding(9)
                .background(
                    message.role == .user
                        ? Color.accentColor
                        : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07))
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contextMenu {
                    Button(L10n.text("action.copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    }
                }
            if message.role != .user { Spacer(minLength: 24) }
        }
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
                    .font(.caption.monospaced()).bold()
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
                Text(replacement.explanation).font(.caption).foregroundStyle(.secondary)
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
                        .font(.caption)
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
                    Label("", systemImage: "chevron.down")
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

private struct DiffText: View {
    let title: String
    let text: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.bold()).foregroundStyle(color)
            ScrollView([.vertical, .horizontal]) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(8)
        .background(color.opacity(0.05))
        .frame(maxWidth: .infinity)
    }
}
