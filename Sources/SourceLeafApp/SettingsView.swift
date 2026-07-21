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
            Section(L10n.text("settings.editor")) {
                Toggle(L10n.text("settings.autoSave"), isOn: $model.configuration.autoSave)
                LabeledContent(L10n.text("settings.autoSaveDelay")) {
                    Stepper(value: $model.configuration.autoSaveDelaySeconds, in: 0.2...5, step: 0.2) {
                        Text(model.configuration.autoSaveDelaySeconds, format: .number.precision(.fractionLength(1))) + Text(" s")
                    }
                }
                Toggle(L10n.text("settings.selectionButton"), isOn: $model.configuration.showSelectionButton)
                Toggle(L10n.text("settings.privateChat"), isOn: $model.configuration.privateChatMode)
            }
            Section(L10n.text("settings.build")) {
                Picker(L10n.text("settings.engine"), selection: $model.configuration.build.engine) {
                    ForEach(BuildEngine.allCases) { engine in Text(L10n.engine(engine)).tag(engine) }
                }
                Toggle(L10n.autoCompile, isOn: $model.configuration.build.autoBuild)
                LabeledContent(L10n.text("settings.compileDelay")) {
                    Stepper(value: $model.configuration.build.debounceSeconds, in: 0.5...5, step: 0.5) {
                        Text(model.configuration.build.debounceSeconds, format: .number.precision(.fractionLength(1))) + Text(" s")
                    }
                }
                Toggle(L10n.text("settings.shellEscape"), isOn: $model.configuration.build.shellEscape)
                if model.configuration.build.engine == .custom {
                    TextField("latexmk {{root}} -outdir={{output}}", text: $model.configuration.build.customCommand)
                        .font(.body.monospaced())
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
                        Image(systemName: profile.kind == .localCodex ? "terminal" : "network")
                        Text(profile.name)
                        Spacer()
                        if profile.enabled { Circle().fill(.green).frame(width: 6, height: 6) }
                    }
                    .tag(profile.id)
                }
                HStack {
                    Button {
                        let profile = ProviderProfile(name: "New Provider", kind: .openAICompatible)
                        model.providerProfiles.append(profile)
                        selectedID = profile.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        guard let id = selectedID,
                              model.providerProfiles.first(where: { $0.id == id })?.kind != .localCodex else { return }
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
            .disabled(profile.kind == .localCodex)
            Toggle(L10n.text("provider.enabled"), isOn: $model.providerProfiles[index].enabled)
            if profile.kind != .localCodex {
                TextField(L10n.text("provider.model"), text: $model.providerProfiles[index].model)
                TextField(L10n.text("provider.baseURL"), text: Binding(
                    get: { model.providerProfiles[index].baseURL ?? "" },
                    set: { model.providerProfiles[index].baseURL = $0.isEmpty ? nil : $0 }
                ))
                SecureField(L10n.text("provider.apiKey"), text: $secret)
                    .onSubmit { model.setSecret(secret, for: profile) }
                Text(L10n.text("provider.keychainHint")).font(.caption).foregroundStyle(.secondary)
            } else {
                Label(L10n.text("provider.localCodexHint"), systemImage: "lock.shield")
                    .font(.caption)
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

    var body: some View {
        List {
            ForEach($model.promptTemplates) { $prompt in
                HStack {
                    Toggle("", isOn: $prompt.enabled).labelsHidden()
                    VStack(alignment: .leading) {
                        Text(Locale.current.language.languageCode?.identifier == "zh" ? prompt.nameZH : prompt.name)
                        Text(prompt.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if prompt.builtIn { Text(L10n.text("prompt.builtIn")).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
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
            Text(L10n.text("storage.locationHint")).font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
