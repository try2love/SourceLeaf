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
            Button(L10n.text("action.ok"), role: .cancel) { model.lastError = nil }
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
                        get: { model.layout.contains(panel) || model.floatingPanels.contains(panel) },
                        set: { _ in model.togglePanel(panel) }
                    ))
                }
            } label: {
                Label(L10n.workspace, systemImage: "rectangle.3.group")
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
                if model.buildRunning { ProgressView().controlSize(.small) }
                else { Label(L10n.compile, systemImage: "play.fill") }
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
    var body: some View {
        HStack(spacing: 0) {
            ActivityBarView()
            Divider()
            DockCanvasView()
        }
    }
}

private struct ActivityBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 4) {
            ForEach(WorkspacePanel.allCases) { panel in
                Button {
                    if model.floatingPanels.contains(panel) { openWindow(value: panel) }
                    else { model.activatePanel(panel) }
                } label: {
                    Image(systemName: panel.symbolName)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                        .background(activityBackground(for: panel), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(L10n.panel(panel))
                .accessibilityLabel(L10n.panel(panel))
            }
            Spacer()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .frame(width: 44)
        .background(.bar)
    }

    private func activityBackground(for panel: WorkspacePanel) -> Color {
        if model.floatingPanels.contains(panel) { return Color.orange.opacity(0.2) }
        return model.layout.contains(panel) ? Color.accentColor.opacity(0.18) : Color.clear
    }
}

private struct DockCanvasView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VSplitView {
            HSplitView {
                ForEach([DockZone.leading, .center, .trailing], id: \.self) { zone in
                    if (model.layout.zones[zone] ?? []).isEmpty {
                        DockZoneView(zone: zone)
                            .frame(minWidth: 38, idealWidth: 44, maxWidth: 64)
                    } else {
                        DockZoneView(zone: zone)
                            .frame(minWidth: zone == .center ? 320 : 210)
                    }
                }
            }
            .frame(minHeight: 420)

            DockZoneView(zone: .bottom)
                .frame(
                    minHeight: (model.layout.zones[.bottom] ?? []).isEmpty ? 28 : 72,
                    idealHeight: (model.layout.zones[.bottom] ?? []).isEmpty ? 28 : 104,
                    maxHeight: (model.layout.zones[.bottom] ?? []).isEmpty ? 36 : 220
                )
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
            if panels.isEmpty {
                emptyDropTarget
            } else {
                tabBar
                Divider()
                if let selected {
                    PanelContentView(panel: selected)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(panels.isEmpty ? 0.35 : 0))
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let panel = WorkspacePanel(rawValue: raw) else { return false }
            model.movePanel(panel, to: zone)
            return true
        }
    }

    private var emptyDropTarget: some View {
        VStack(spacing: 5) {
            Image(systemName: "rectangle.dashed")
            if zone == .bottom { Text(L10n.text("dock.dropBottom")) }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(panels) { panel in
                HStack(spacing: 5) {
                    Button { model.selectPanel(panel, in: zone) } label: {
                        Label(L10n.panel(panel), systemImage: panel.symbolName)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Section(L10n.text("dock.moveTo")) {
                            ForEach(DockZone.allCases, id: \.self) { destination in
                                let title = L10n.dockZone(destination)
                                Button(title) { model.movePanel(panel, to: destination) }
                                    .disabled(destination == zone)
                            }
                        }
                        Divider()
                        Button(L10n.text("action.detach")) {
                            openWindow(value: panel)
                            model.detachPanel(panel)
                        }
                        Button(L10n.text("action.hide")) { model.closePanel(panel) }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(selected == panel ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .draggable(panel.rawValue)
                .help(L10n.text("dock.dragHint"))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .background(.bar)
    }
}

struct PanelContentView: View {
    let panel: WorkspacePanel

    @ViewBuilder
    var body: some View {
        switch panel {
        case .project: ProjectPanel()
        case .source: SourcePanel()
        case .image: ImagePanel()
        case .pdf: PDFPanel()
        case .codex: CodexPanel()
        case .buildLog: BuildLogPanel()
        case .history: HistoryPanel()
        }
    }
}

struct FloatingPanelView: View {
    @EnvironmentObject private var model: AppModel
    let panel: WorkspacePanel

    var body: some View {
        PanelContentView(panel: panel)
            .onDisappear { model.restoreFloatingPanel(panel) }
    }
}

extension WorkspacePanel {
    var symbolName: String {
        switch self {
        case .project: "folder"
        case .source: "chevron.left.forwardslash.chevron.right"
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .codex: "sparkles"
        case .buildLog: "terminal"
        case .history: "clock.arrow.circlepath"
        }
    }
}
