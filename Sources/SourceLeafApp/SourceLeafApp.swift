import SwiftUI
import SourceLeafCore

@main
struct SourceLeafApplication: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: model.appLanguage.localeIdentifier))
                .dynamicTypeSize(InterfaceFontScale.dynamicTypeSize(for: model.interfaceFontScale))
                .preferredColorScheme(model.editorTheme.colorScheme)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            SourceLeafCommands(model: model)
        }

        WindowGroup(L10n.text("window.panelTitle"), for: WorkspacePanel.self) { panel in
            if let panel = panel.wrappedValue {
                FloatingPanelView(panel: panel)
                    .environmentObject(model)
                    .environment(\.locale, Locale(identifier: model.appLanguage.localeIdentifier))
                    .dynamicTypeSize(InterfaceFontScale.dynamicTypeSize(for: model.interfaceFontScale))
                    .preferredColorScheme(model.editorTheme.colorScheme)
                    .frame(minWidth: 420, minHeight: 360)
            }
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: model.appLanguage.localeIdentifier))
                .dynamicTypeSize(InterfaceFontScale.dynamicTypeSize(for: model.interfaceFontScale))
                .preferredColorScheme(model.editorTheme.colorScheme)
                .frame(minWidth: 680, minHeight: 540)
        }
    }
}

private struct SourceLeafCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.openProject) { model.presentOpenProjectPanel() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button(L10n.text("action.save")) { model.saveNow() }
                .keyboardShortcut("s")
                .disabled(!model.canSaveCurrentFile || !model.hasUnsavedChanges)
        }
        CommandMenu(L10n.workspace) {
            ForEach(WorkspacePanel.allCases) { panel in
                Button(model.layout.contains(panel) ? L10n.hide(panel) : L10n.show(panel)) {
                    model.togglePanel(panel)
                }
            }
        }
        CommandMenu(L10n.build) {
            Button(L10n.compile) { model.compile() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Toggle(L10n.autoCompile, isOn: Binding(
                get: { model.configuration.build.autoBuild },
                set: {
                    model.configuration.build.autoBuild = $0
                    model.persistConfiguration()
                }
            ))
        }
        CommandMenu(L10n.text("source.menu.format")) {
            Button(L10n.text("source.format.bold")) { model.performLaTeXEdit(.bold) }
                .keyboardShortcut("b", modifiers: .command)
            Button(L10n.text("source.format.italic")) { model.performLaTeXEdit(.italic) }
                .keyboardShortcut("i", modifiers: .command)
            Button(L10n.text("source.format.underline")) { model.performLaTeXEdit(.underline) }
                .keyboardShortcut("u", modifiers: .command)
            Divider()
            Button(L10n.text("source.findReplace")) {
                NotificationCenter.default.post(name: .sourceLeafShowFind, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }
    }
}
