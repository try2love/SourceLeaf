import SwiftUI
import SourceLeafCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(L10n.text("settings.general"), systemImage: "gear") }
            ProviderSettingsView()
                .tabItem { Label(L10n.text("settings.providers"), systemImage: "sparkles") }
            PromptSettingsView()
                .tabItem { Label(L10n.text("settings.prompts"), systemImage: "text.badge.star") }
            StorageSettingsView()
                .tabItem { Label(L10n.text("settings.storage"), systemImage: "internaldrive") }
        }
        .padding(16)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section(L10n.text("settings.language")) {
                Picker(L10n.text("settings.interfaceLanguage"), selection: Binding(
                    get: { model.appLanguage },
                    set: { model.setAppLanguage($0) }
                )) {
                    Text(L10n.text("language.system")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("简体中文").tag(AppLanguage.simplifiedChinese)
                }
                LabeledContent(L10n.text("settings.interfaceFontSize")) {
                    HStack {
                        Slider(value: Binding(
                            get: { model.interfaceFontScale },
                            set: { model.setInterfaceFontScale($0) }
                        ), in: 0.85...1.6, step: 0.05)
                        Text("\(Int((model.interfaceFontScale * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 46, alignment: .trailing)
                    }
                    .frame(width: 250)
                }
            }
            Section(L10n.text("settings.editor")) {
                Picker(L10n.text("settings.theme"), selection: Binding(
                    get: { model.editorTheme },
                    set: { model.setEditorTheme($0) }
                )) {
                    Text(L10n.text("theme.system")).tag(EditorTheme.system)
                    Text(L10n.text("theme.light")).tag(EditorTheme.light)
                    Text(L10n.text("theme.dark")).tag(EditorTheme.dark)
                }
                Picker(L10n.text("settings.editorFont"), selection: Binding(
                    get: { model.editorFontFamily },
                    set: { model.setEditorFontFamily($0) }
                )) {
                    Text(L10n.text("font.systemMonospaced")).tag(EditorFontCatalog.systemMonospaced)
                    Divider()
                    ForEach(EditorFontCatalog.availableFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                LabeledContent(L10n.text("settings.editorFontSize")) {
                    Stepper(value: Binding(
                        get: { model.editorFontSize },
                        set: { model.setEditorFontSize($0) }
                    ), in: 10...32, step: 1) {
                        Text("\(Int(model.editorFontSize)) pt")
                            .monospacedDigit()
                    }
                }
                Toggle(L10n.text("settings.autoSave"), isOn: Binding(
                    get: { model.configuration.autoSave },
                    set: { model.setAutoSave($0) }
                ))
                LabeledContent(L10n.text("settings.autoSaveDelay")) {
                    Stepper(value: $model.configuration.autoSaveDelaySeconds, in: 0.2...5, step: 0.2) {
                        Text(model.configuration.autoSaveDelaySeconds, format: .number.precision(.fractionLength(1))) + Text(" s")
                    }
                }
                Toggle(L10n.text("settings.selectionButton"), isOn: $model.configuration.showSelectionButton)
                Toggle(L10n.text("settings.privateChat"), isOn: $model.configuration.privateChatMode)
                Picker(L10n.text("settings.chatSendBehavior"), selection: $model.configuration.chatSendBehavior) {
                    Text(L10n.text("chat.sendWithEnter")).tag(ChatSendBehavior.enter)
                    Text(L10n.text("chat.sendWithShiftEnter")).tag(ChatSendBehavior.shiftEnter)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("settings.systemPrompt"))
                    TextEditor(text: $model.configuration.systemPrompt)
                        .sourceLeafFont(.body, design: .monospaced)
                        .frame(minHeight: 90)
                        .padding(5)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary))
                    Text(L10n.text("settings.systemPromptHint"))
                        .sourceLeafFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section(L10n.text("settings.build")) {
                Picker(L10n.text("settings.engine"), selection: $model.configuration.build.engine) {
                    ForEach(BuildEngine.allCases) { engine in Text(L10n.engine(engine)).tag(engine) }
                }
                Toggle(L10n.autoCompile, isOn: Binding(
                    get: { model.configuration.build.autoBuild },
                    set: { model.setAutoBuild($0) }
                ))
                .disabled(!model.canEnableAutoBuild)
                .help(model.canEnableAutoBuild ? L10n.autoCompile : L10n.text("build.autoCompileRequiresAutoSave"))
                LabeledContent(L10n.text("settings.compileDelay")) {
                    Stepper(value: $model.configuration.build.debounceSeconds, in: 0.5...5, step: 0.5) {
                        Text(model.configuration.build.debounceSeconds, format: .number.precision(.fractionLength(1))) + Text(" s")
                    }
                }
                Toggle(L10n.text("settings.shellEscape"), isOn: $model.configuration.build.shellEscape)
                Toggle(L10n.text("settings.trialCompile"), isOn: $model.configuration.build.trialCompileBeforeAccept)
                if model.configuration.build.engine == .custom {
                    TextField("latexmk {{root}} -outdir={{output}}", text: $model.configuration.build.customCommand)
                        .sourceLeafFont(.body, design: .monospaced)
                }
            }
            Section(L10n.text("settings.context")) {
                Picker(L10n.text("settings.defaultContext"), selection: $model.configuration.defaultContextScope) {
                    ForEach(ContextScope.allCases) { scope in Text(L10n.context(scope)).tag(scope) }
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { model.persistConfiguration() }
    }
}

private struct ProviderSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedID: UUID?

    private var selectedIndex: Int? { model.providerProfiles.firstIndex { $0.id == selectedID } }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(model.providerProfiles, selection: $selectedID) { profile in
                    HStack {
                        Image(systemName: [.localCodex, .codeBuddy].contains(profile.kind) ? "terminal" : "network")
                        Text(profile.name)
                        Spacer()
                        if profile.enabled { Circle().fill(.green).frame(width: 6, height: 6) }
                    }
                    .tag(profile.id)
                }
                HStack {
                    Button {
                        let profile = ProviderProfile(name: L10n.text("provider.newName"), kind: .openAICompatible)
                        model.providerProfiles.append(profile)
                        selectedID = profile.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        guard let id = selectedID,
                              let kind = model.providerProfiles.first(where: { $0.id == id })?.kind,
                              ![.localCodex, .codeBuddy].contains(kind) else { return }
                        model.providerProfiles.removeAll { $0.id == id }
                        selectedID = model.providerProfiles.first?.id
                    } label: { Image(systemName: "minus") }
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(7)
            }
            .frame(minWidth: 190)

            if let index = selectedIndex {
                ProviderEditor(index: index)
                    .frame(minWidth: 340)
            } else {
                ContentUnavailableView(L10n.text("provider.select"), systemImage: "sparkles")
            }
        }
        .onAppear { selectedID = model.providerProfiles.first?.id }
        .onDisappear { model.saveProviderProfiles() }
    }
}

private struct ProviderEditor: View {
    @EnvironmentObject private var model: AppModel
    let index: Int
    @State private var secret = ""

    private var profile: ProviderProfile { model.providerProfiles[index] }

    var body: some View {
        Form {
            TextField(L10n.text("provider.name"), text: $model.providerProfiles[index].name)
            Picker(L10n.text("provider.kind"), selection: $model.providerProfiles[index].kind) {
                ForEach(ProviderKind.allCases) { kind in Text(L10n.provider(kind)).tag(kind) }
            }
            .disabled([.localCodex, .codeBuddy].contains(profile.kind))
            Toggle(L10n.text("provider.enabled"), isOn: $model.providerProfiles[index].enabled)
            TextField(L10n.text("provider.model"), text: $model.providerProfiles[index].model)
            if [.localCodex, .openAI, .openAICompatible].contains(profile.kind) {
                Picker(L10n.text("provider.reasoning"), selection: $model.providerProfiles[index].reasoningEffort) {
                    Text(L10n.text("provider.reasoningDefault")).tag(Optional<ModelReasoningEffort>.none)
                    ForEach(ModelReasoningEffort.allCases) { effort in
                        Text(L10n.text("reasoning.\(effort.rawValue)")).tag(Optional(effort))
                    }
                }
            }
            if ![.localCodex, .codeBuddy].contains(profile.kind) {
                TextField(L10n.text("provider.baseURL"), text: Binding(
                    get: { model.providerProfiles[index].baseURL ?? "" },
                    set: { model.providerProfiles[index].baseURL = $0.isEmpty ? nil : $0 }
                ))
                SecureField(L10n.text("provider.apiKey"), text: $secret)
                    .onSubmit { model.setSecret(secret, for: profile) }
                Text(L10n.text("provider.keychainHint")).sourceLeafFont(.caption).foregroundStyle(.secondary)
            } else {
                Label(
                    L10n.text(profile.kind == .codeBuddy ? "provider.codeBuddyHint" : "provider.localCodexHint"),
                    systemImage: "lock.shield"
                )
                    .sourceLeafFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { secret = model.secret(for: profile) }
        .onChange(of: index) { _, _ in secret = model.secret(for: profile) }
        .onDisappear {
            if !secret.isEmpty { model.setSecret(secret, for: profile) }
            model.saveProviderProfiles()
        }
    }
}

private struct PromptSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedID: String?

    private var selectedIndex: Int? { model.promptTemplates.firstIndex { $0.id == selectedID } }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(model.promptTemplates, selection: $selectedID) { prompt in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.appLanguage.isChinese ? prompt.nameZH : prompt.name)
                        HStack {
                            Text(prompt.id).sourceLeafFont(.caption2, design: .monospaced).foregroundStyle(.secondary)
                            if prompt.builtIn {
                                Text(L10n.text("prompt.builtIn"))
                                    .sourceLeafFont(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tag(prompt.id)
                }
                HStack {
                    Button {
                        selectedID = model.addPrompt().id
                    } label: { Image(systemName: "plus") }
                    Button {
                        guard let index = selectedIndex else { return }
                        selectedID = model.duplicatePrompt(model.promptTemplates[index]).id
                    } label: { Image(systemName: "doc.on.doc") }
                    .disabled(selectedIndex == nil)
                    Button {
                        guard let index = selectedIndex else { return }
                        let prompt = model.promptTemplates[index]
                        model.deletePrompt(prompt)
                        selectedID = model.promptTemplates.first?.id
                    } label: { Image(systemName: "trash") }
                    .disabled(selectedIndex.map { model.promptTemplates[$0].builtIn } ?? true)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(7)
            }
            .frame(minWidth: 220)

            if let index = selectedIndex {
                PromptEditor(index: index)
                    .frame(minWidth: 360)
            } else {
                ContentUnavailableView(L10n.text("prompt.select"), systemImage: "text.badge.star")
            }
        }
        .onAppear { selectedID = model.promptTemplates.first?.id }
        .onChange(of: model.promptTemplates) { _, _ in model.savePromptTemplates() }
    }
}

struct PromptEditor: View {
    @EnvironmentObject private var model: AppModel
    let index: Int
    @State private var language: PromptBodyLanguage = .english

    private var prompt: PromptTemplate { model.promptTemplates[index] }
    private var bodyBinding: Binding<String> {
        language == .english
            ? $model.promptTemplates[index].body
            : $model.promptTemplates[index].bodyZH
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle(L10n.text("prompt.enabled"), isOn: $model.promptTemplates[index].enabled)
                Spacer()
                Picker("", selection: $language) {
                    Text(L10n.text("prompt.languageEnglish")).tag(PromptBodyLanguage.english)
                    Text(L10n.text("prompt.languageChinese")).tag(PromptBodyLanguage.simplifiedChinese)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text(L10n.text("prompt.nameEnglish")).foregroundStyle(.secondary)
                    TextField("", text: $model.promptTemplates[index].name)
                        .disabled(prompt.builtIn)
                }
                GridRow {
                    Text(L10n.text("prompt.nameChinese")).foregroundStyle(.secondary)
                    TextField("", text: $model.promptTemplates[index].nameZH)
                        .disabled(prompt.builtIn)
                }
            }
            Text(language == .english ? L10n.text("prompt.bodyEnglish") : L10n.text("prompt.bodyChinese"))
                .sourceLeafFont(.headline, weight: .semibold)
            Group {
                if prompt.builtIn {
                    ScrollView {
                        Text(bodyBinding.wrappedValue)
                            .sourceLeafFont(.body, design: .monospaced)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10)
                    }
                } else {
                    TextEditor(text: bodyBinding)
                        .sourceLeafFont(.body, design: .monospaced)
                        .padding(7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            .layoutPriority(1)
            if !prompt.variables.isEmpty {
                LabeledContent(L10n.text("prompt.variables")) {
                    Text(prompt.variables.map { "{{\($0)}}" }.joined(separator: ", "))
                        .sourceLeafFont(.caption, design: .monospaced)
                        .textSelection(.enabled)
                }
            }
            if prompt.builtIn {
                HStack {
                    Label(L10n.text("prompt.readOnlyHint"), systemImage: "lock")
                        .sourceLeafFont(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.text("prompt.duplicateToEdit")) {
                        _ = model.duplicatePrompt(prompt)
                    }
                }
            }
        }
        .padding(16)
        .onAppear {
            language = model.appLanguage.isChinese ? .simplifiedChinese : .english
        }
    }
}

private enum PromptBodyLanguage: String, CaseIterable, Identifiable {
    case english
    case simplifiedChinese
    var id: String { rawValue }
}

private struct StorageSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section(L10n.text("storage.cache")) {
                Button(L10n.text("storage.clearBuild")) { model.clearBuildCache() }
            }
            Section(L10n.text("storage.history")) {
                Button(L10n.text("storage.clearChat"), role: .destructive) { model.clearChatHistory() }
                Button(L10n.text("storage.clearAIHistory"), role: .destructive) { model.clearAIHistory() }
            }
            Text(L10n.text("storage.locationHint")).sourceLeafFont(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
