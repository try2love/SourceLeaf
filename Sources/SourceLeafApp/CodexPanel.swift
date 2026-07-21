import SwiftUI
import SourceLeafCore

struct CodexPanel: View {
    @EnvironmentObject private var model: AppModel

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
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker(L10n.text("ai.provider"), selection: $model.selectedProviderID) {
                ForEach(model.providerProfiles.filter(\.enabled)) { profile in
                    Text(profile.name).tag(Optional(profile.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 150)
            Picker(L10n.text("ai.context"), selection: $model.contextScope) {
                ForEach(ContextScope.allCases) { scope in
                    Text(L10n.context(scope)).tag(scope)
                }
            }
            .labelsHidden()
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
            Menu {
                ForEach(model.promptTemplates.filter(\.enabled)) { prompt in
                    Button(model.appLanguage.isChinese ? prompt.nameZH : prompt.name) {
                        model.usePrompt(prompt)
                    }
                }
            } label: {
                Label(L10n.text("ai.prompts"), systemImage: "text.badge.star")
            }
            .labelStyle(.iconOnly)
            Spacer()
        }
        .padding(7)
        .background(.bar)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                TextEditor(text: $model.instruction)
                    .font(.body)
                    .frame(minHeight: 52, maxHeight: 120)
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
}

private struct ChatBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 24) }
            Text(message.text)
                .textSelection(.enabled)
                .padding(9)
                .background(message.role == .user ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
