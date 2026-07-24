import AppKit
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
        .background(MainWindowCloseGuard(model: model).frame(width: 0, height: 0))
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
            Menu {
                Picker(L10n.text("settings.theme"), selection: Binding(
                    get: { model.editorTheme },
                    set: { model.setEditorTheme($0) }
                )) {
                    Text(L10n.text("theme.system")).tag(EditorTheme.system)
                    Text(L10n.text("theme.light")).tag(EditorTheme.light)
                    Text(L10n.text("theme.dark")).tag(EditorTheme.dark)
                }
            } label: {
                Label(L10n.text("settings.theme"), systemImage: model.editorTheme == .dark ? "moon.fill" : "circle.lefthalf.filled")
            }
            .help(L10n.text("settings.theme"))

            Button {
                model.saveNow()
            } label: {
                Label(L10n.text("action.save"), systemImage: "square.and.arrow.down")
            }
            .disabled(!model.canSaveCurrentFile || !model.hasUnsavedChanges)
            .help(L10n.text("action.save"))

            Toggle(isOn: Binding(
                get: { model.configuration.build.autoBuild },
                set: { model.setAutoBuild($0) }
            )) {
                Label(L10n.autoCompile, systemImage: "bolt")
            }
            .toggleStyle(.button)
            .help(model.configuration.build.autoBuild
                ? L10n.text("build.autoCompileOn")
                : (model.canEnableAutoBuild ? L10n.text("build.autoCompileOff") : L10n.text("build.autoCompileRequiresAutoSave")))
            .disabled(!model.canEnableAutoBuild)

            Button {
                if model.buildRunning { model.cancelCompile() }
                else { model.compile() }
            } label: {
                if model.buildRunning {
                    Label(L10n.text("build.stop"), systemImage: "stop.fill")
                        .foregroundStyle(.red)
                } else {
                    Label(L10n.compile, systemImage: "play.fill")
                }
            }
            .disabled(model.projectRoot == nil)
            .help(model.buildRunning ? L10n.text("build.stop") : L10n.compile)
        }
        ToolbarItem(placement: .status) {
            Text(model.statusText)
                .sourceLeafFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct MainWindowCloseGuard: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> WindowCloseGuardHostView {
        let view = WindowCloseGuardHostView()
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.install(on: window)
        }
        return view
    }

    func updateNSView(_ view: WindowCloseGuardHostView, context: Context) {
        context.coordinator.model = model
        if let window = view.window {
            context.coordinator.install(on: window)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        weak var model: AppModel?
        weak var installedWindow: NSWindow?
        weak var originalDelegate: NSWindowDelegate?

        init(model: AppModel) {
            self.model = model
        }

        func install(on window: NSWindow) {
            guard installedWindow !== window else { return }
            originalDelegate = window.delegate
            installedWindow = window
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if originalDelegate?.windowShouldClose?(sender) == false {
                return false
            }
            return model?.requestMainWindowClose() ?? true
        }

        func windowWillClose(_ notification: Notification) {
            originalDelegate?.windowWillClose?(notification)
        }
    }
}

private final class WindowCloseGuardHostView: NSView {
    var onWindowChanged: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindowChanged?(window)
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
                        .font(.system(size: 17 * model.interfaceFontScale, weight: .medium))
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
            ResizableDockColumns()
                .frame(minHeight: 420)
                .layoutPriority(1)

            DockZoneView(zone: .bottom)
                .frame(
                    minHeight: (model.layout.zones[.bottom] ?? []).isEmpty ? 28 : 58,
                    idealHeight: (model.layout.zones[.bottom] ?? []).isEmpty ? 28 : 72,
                    maxHeight: (model.layout.zones[.bottom] ?? []).isEmpty ? 36 : 140
                )
                .layoutPriority(-1)
        }
    }
}

private struct ResizableDockColumns: View {
    @EnvironmentObject private var model: AppModel
    @State private var leadingWidth: CGFloat = 260
    @State private var trailingWidth: CGFloat = 390
    @State private var leadingDragStart: CGFloat?
    @State private var trailingDragStart: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let leadingEmpty = (model.layout.zones[.leading] ?? []).isEmpty
            let trailingEmpty = (model.layout.zones[.trailing] ?? []).isEmpty
            let left = leadingEmpty ? 44 : min(max(210, leadingWidth), max(210, geometry.size.width - 550))
            let right = trailingEmpty ? 44 : min(max(210, trailingWidth), max(210, geometry.size.width - left - 330))
            HStack(spacing: 0) {
                DockZoneView(zone: .leading).frame(width: left)
                WideDockDivider {
                    if leadingDragStart == nil { leadingDragStart = leadingWidth }
                    leadingWidth = max(210, (leadingDragStart ?? leadingWidth) + $0)
                } onEnded: { leadingDragStart = nil }
                DockZoneView(zone: .center).frame(minWidth: 320, maxWidth: .infinity)
                WideDockDivider {
                    if trailingDragStart == nil { trailingDragStart = trailingWidth }
                    trailingWidth = max(210, (trailingDragStart ?? trailingWidth) - $0)
                } onEnded: { trailingDragStart = nil }
                DockZoneView(zone: .trailing).frame(width: right)
            }
        }
    }
}

private struct WideDockDivider: View {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void
    @State private var cursorIsPushed = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 12)
            .overlay(Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1))
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering, !cursorIsPushed {
                    NSCursor.resizeLeftRight.push()
                    cursorIsPushed = true
                } else if !hovering, cursorIsPushed {
                    NSCursor.pop()
                    cursorIsPushed = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onChanged($0.translation.width) }
                    .onEnded { _ in onEnded() }
            )
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .help(L10n.text("workspace.resizePanels"))
            .onDisappear {
                if cursorIsPushed {
                    NSCursor.pop()
                    cursorIsPushed = false
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
        .sourceLeafFont(.caption2)
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
                            .sourceLeafFont(.caption)
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
                .contentShape(Rectangle())
                .onTapGesture { model.selectPanel(panel, in: zone) }
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
        case .codex: "bubble.left.and.bubble.right"
        case .buildLog: "terminal"
        case .history: "clock.arrow.circlepath"
        }
    }
}
