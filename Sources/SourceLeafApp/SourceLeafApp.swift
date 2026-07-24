import SwiftUI
import SourceLeafCore

@main
struct SourceLeafApplication: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(SourceLeafLifecycleDelegate.self) private var lifecycleDelegate

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
                .onAppear { lifecycleDelegate.model = model }
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: model.appLanguage.localeIdentifier))
                .dynamicTypeSize(InterfaceFontScale.dynamicTypeSize(for: model.interfaceFontScale))
                .environment(\.sourceLeafInterfaceScale, model.interfaceFontScale)
                .font(.system(size: 13 * model.interfaceFontScale))
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
                    .environment(\.sourceLeafInterfaceScale, model.interfaceFontScale)
                    .font(.system(size: 13 * model.interfaceFontScale))
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
                .environment(\.sourceLeafInterfaceScale, model.interfaceFontScale)
                .font(.system(size: 13 * model.interfaceFontScale))
                .preferredColorScheme(model.editorTheme.colorScheme)
                .frame(minWidth: 680, minHeight: 540)
        }
    }
}

@MainActor
final class SourceLeafLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.applicationTerminationReply() ?? .terminateNow
    }
}

struct SourceLeafMenuCommandSpec: Equatable {
    var command: LaTeXEditCommand
    var titleKey: String
    var key: KeyEquivalent
    var modifiers: EventModifiers

    static let math: [SourceLeafMenuCommandSpec] = [
        SourceLeafMenuCommandSpec(command: .inlineMath, titleKey: "source.math.inline", key: "m", modifiers: [.command, .shift]),
        SourceLeafMenuCommandSpec(command: .displayMath, titleKey: "source.math.display", key: "m", modifiers: [.command, .option]),
        SourceLeafMenuCommandSpec(command: .equation, titleKey: "source.math.equation", key: "e", modifiers: [.command, .option]),
        SourceLeafMenuCommandSpec(command: .fraction, titleKey: "source.math.fraction", key: "/", modifiers: [.command, .option])
    ]

    static let insert: [SourceLeafMenuCommandSpec] = [
        SourceLeafMenuCommandSpec(command: .table, titleKey: "source.insert.table", key: "t", modifiers: [.command, .option]),
        SourceLeafMenuCommandSpec(command: .figure, titleKey: "source.insert.figure", key: "i", modifiers: [.command, .option]),
        SourceLeafMenuCommandSpec(command: .cite, titleKey: "source.insert.cite", key: "c", modifiers: [.command, .shift]),
        SourceLeafMenuCommandSpec(command: .reference, titleKey: "source.insert.reference", key: "r", modifiers: [.command, .shift]),
        SourceLeafMenuCommandSpec(command: .label, titleKey: "source.insert.label", key: "l", modifiers: [.command, .shift])
    ]
}

private struct SourceLeafCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button(L10n.text("action.quit")) { model.requestQuit() }
                .keyboardShortcut("q", modifiers: .command)
        }
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
                set: { model.setAutoBuild($0) }
            ))
            .disabled(!model.canEnableAutoBuild)
        }
        CommandMenu(L10n.text("source.menu.format")) {
            Button(L10n.text("source.format.bold")) { model.performLaTeXEdit(.bold) }
                .keyboardShortcut("b", modifiers: .command)
            Button(L10n.text("source.format.italic")) { model.performLaTeXEdit(.italic) }
                .keyboardShortcut("i", modifiers: .command)
            Button(L10n.text("source.format.underline")) { model.performLaTeXEdit(.underline) }
                .keyboardShortcut("u", modifiers: .command)
            Button(L10n.text("source.format.toggleComment")) { model.performLaTeXEdit(.toggleComment) }
                .keyboardShortcut("/", modifiers: .command)
            Button(L10n.text("source.format.indent")) { model.performLaTeXEdit(.indentLines) }
                .keyboardShortcut("]", modifiers: .command)
            Button(L10n.text("source.format.outdent")) { model.performLaTeXEdit(.outdentLines) }
                .keyboardShortcut("[", modifiers: .command)
            Divider()
            Button(L10n.text("source.findReplace")) {
                NotificationCenter.default.post(name: .sourceLeafShowFind, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
        CommandMenu(L10n.text("source.toolbar.math")) {
            ForEach(SourceLeafMenuCommandSpec.math, id: \.command) { spec in
                latexMenuButton(spec)
            }
        }
        CommandMenu(L10n.text("source.toolbar.insert")) {
            ForEach(SourceLeafMenuCommandSpec.insert, id: \.command) { spec in
                latexMenuButton(spec)
            }
        }
    }

    private func latexMenuButton(_ spec: SourceLeafMenuCommandSpec) -> some View {
        Button(L10n.text(spec.titleKey)) {
            model.performLaTeXEdit(spec.command)
        }
        .keyboardShortcut(spec.key, modifiers: spec.modifiers)
    }
}
