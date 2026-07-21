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
                    .frame(minWidth: 420, minHeight: 360)
            }
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: model.appLanguage.localeIdentifier))
                .frame(width: 680, height: 540)
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
        CommandMenu(L10n.workspace) {
            ForEach(WorkspacePanel.allCases) { panel in
                Button(model.layout.contains(panel) ? L10n.hide(panel) : L10n.show(panel)) {
                    model.togglePanel(panel)
                }
            }
        }
        CommandMenu(L10n.build) {
            Button(L10n.compile) { model.compile() }
                .keyboardShortcut("b")
            Toggle(L10n.autoCompile, isOn: Binding(
                get: { model.configuration.build.autoBuild },
                set: {
                    model.configuration.build.autoBuild = $0
                    model.persistConfiguration()
                }
            ))
        }
    }
}
