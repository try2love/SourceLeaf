import SwiftUI
import SourceLeafCore

struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.projectRoot == nil {
                ContentUnavailableView {
                    Label("SourceLeaf", systemImage: "leaf")
                } description: {
                    Text(L10n.noProject)
                } actions: {
                    Button(L10n.openProject) { model.presentOpenProjectPanel() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                DockWorkspaceView()
            }
        }
        .toolbar { workspaceToolbar }
        .alert("SourceLeaf", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                ForEach(WorkspacePanel.allCases) { panel in
                    Toggle(L10n.panel(panel), isOn: Binding(
                        get: { model.layout.contains(panel) },
                        set: { _ in model.togglePanel(panel) }
                    ))
                }
            } label: {
                Label(L10n.workspace, systemImage: "sidebar.left")
            }
        }
        ToolbarItemGroup {
            Toggle(isOn: Binding(
                get: { model.configuration.build.autoBuild },
                set: {
                    model.configuration.build.autoBuild = $0
                    model.persistConfiguration()
                }
            )) {
                Label(L10n.autoCompile, systemImage: "bolt")
            }
            .toggleStyle(.button)

            Button { model.compile() } label: {
                if model.buildRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L10n.compile, systemImage: "play.fill")
                }
            }
            .disabled(model.projectRoot == nil || model.buildRunning)
        }
        ToolbarItem(placement: .status) {
            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct DockWorkspaceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VSplitView {
            HSplitView {
                ForEach([DockZone.leading, .center, .trailing], id: \.self) { zone in
                    if !(model.layout.zones[zone] ?? []).isEmpty {
                        DockZoneView(zone: zone)
                            .frame(minWidth: zone == .center ? 360 : 260)
                    }
                }
            }
            if !(model.layout.zones[.bottom] ?? []).isEmpty {
                DockZoneView(zone: .bottom)
                    .frame(minHeight: 150, idealHeight: 220)
            }
        }
    }
}

struct DockZoneView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let zone: DockZone

    private var panels: [WorkspacePanel] { model.layout.zones[zone] ?? [] }
    private var selected: WorkspacePanel? {
        if let selected = model.layout.selected[zone], panels.contains(selected) { return selected }
        return panels.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(panels) { panel in
                    HStack(spacing: 5) {
                        Button {
                            model.selectPanel(panel, in: zone)
                        } label: {
                            Label(L10n.panel(panel), systemImage: panel.symbolName)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        Button {
                            openWindow(value: panel)
                            model.closePanel(panel)
                        } label: {
                            Image(systemName: "macwindow.on.rectangle")
                        }
                        .buttonStyle(.plain)
                        .help(L10n.text("action.detach"))
                        Button { model.closePanel(panel) } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(selected == panel ? Color.accentColor.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .draggable(panel.rawValue)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5)
            .background(.bar)

            Divider()

            if let selected {
                PanelContentView(panel: selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let panel = WorkspacePanel(rawValue: raw) else { return false }
            model.movePanel(panel, to: zone)
            return true
        }
    }
}

struct PanelContentView: View {
    let panel: WorkspacePanel

    @ViewBuilder
    var body: some View {
        switch panel {
        case .project: ProjectPanel()
        case .source: SourcePanel()
        case .pdf: PDFPanel()
        case .codex: CodexPanel()
        case .buildLog: BuildLogPanel()
        case .history: HistoryPanel()
        }
    }
}

struct FloatingPanelView: View {
    let panel: WorkspacePanel
    var body: some View { PanelContentView(panel: panel) }
}

private extension WorkspacePanel {
    var symbolName: String {
        switch self {
        case .project: "folder"
        case .source: "chevron.left.forwardslash.chevron.right"
        case .pdf: "doc.richtext"
        case .codex: "sparkles"
        case .buildLog: "terminal"
        case .history: "clock.arrow.circlepath"
        }
    }
}
