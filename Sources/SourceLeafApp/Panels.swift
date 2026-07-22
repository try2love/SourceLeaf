import AppKit
import PDFKit
import QuickLookUI
import SwiftUI
import SourceLeafCore

struct ProjectPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    private var filteredFiles: [ProjectFile] {
        guard !query.isEmpty else { return model.projectFiles }
        return model.projectFiles.filter { $0.relativePath.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(L10n.text("project.filter"), text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            if !model.outline.isEmpty {
                VSplitView {
                    fileBrowser
                        .frame(minHeight: 100)
                    outlinePane
                }
            } else {
                fileBrowser
            }
        }
    }

    @ViewBuilder
    private var fileBrowser: some View {
        if query.isEmpty {
            List {
                ForEach(model.projectTree) { node in
                    ProjectTreeBranch(node: node)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))
        } else {
            List(filteredFiles) { file in
                Button { model.openFile(file) } label: {
                    Label(file.relativePath, systemImage: file.symbolName)
                        .font(.system(
                            size: 11 * model.interfaceFontScale,
                            design: file.kind == .tex ? .monospaced : .default
                        ))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var outlinePane: some View {
        VStack(spacing: 0) {
            Button {
                model.toggleProjectOutline()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.projectOutlineExpanded ? "chevron.down" : "chevron.right")
                    Image(systemName: "list.bullet.indent")
                    Text(L10n.text("project.outline"))
                    Spacer()
                    Text("\(model.outline.count)")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sourceLeafFont(.caption, weight: .semibold)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(.bar)
            .help(model.projectOutlineExpanded
                ? L10n.text("project.outlineCollapse")
                : L10n.text("project.outlineExpand"))

            if model.projectOutlineExpanded {
                List {
                    OutlineGroup(ProjectIndexer.outlineTree(from: model.outline), children: \.childNodes) { node in
                    Button { model.jumpToOutline(node.item) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "number")
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(node.item.title)
                                if let path = node.item.relativePath,
                                   path != model.selectedFile?.relativePath {
                                    Text(path)
                                        .sourceLeafFont(.caption2, design: .monospaced)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("\(node.item.line)").foregroundStyle(.tertiary)
                        }
                        .sourceLeafFont(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(
            minHeight: model.projectOutlineExpanded ? 80 : 28,
            idealHeight: model.projectOutlineExpanded ? 190 : 28,
            maxHeight: model.projectOutlineExpanded ? .infinity : 28
        )
    }
}

private struct ProjectTreeBranch: View {
    @EnvironmentObject private var model: AppModel
    let node: ProjectTreeNode
    @State private var expanded = true

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(node.children ?? []) { child in
                    ProjectTreeBranch(node: child)
                }
            } label: {
                Label(node.name, systemImage: expanded ? "folder.fill" : "folder")
                    .font(.system(size: 11 * model.interfaceFontScale))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { expanded.toggle() }
                    .help(expanded ? L10n.text("project.folderCollapse") : L10n.text("project.folderExpand"))
            }
        } else {
            ProjectTreeRow(node: node)
        }
    }
}

private struct ProjectTreeRow: View {
    @EnvironmentObject private var model: AppModel
    let node: ProjectTreeNode

    var body: some View {
        if let file = node.file {
            Button { model.openFile(file) } label: {
                Label(node.name, systemImage: file.symbolName)
                    .font(.system(
                        size: 11 * model.interfaceFontScale,
                        design: file.kind == .tex ? .monospaced : .default
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(format: L10n.text("project.openFile"), file.relativePath))
            .contextMenu {
                if file.kind == .tex {
                    Button(L10n.text("project.setRoot")) {
                        model.configuration.rootDocument = file.relativePath
                        model.persistConfiguration()
                    }
                }
            }
        } else {
            Label(node.name, systemImage: "folder")
                .sourceLeafFont(.caption)
        }
    }
}

struct ImagePanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var zoomScale = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "photo")
                Text(model.selectedImageFile?.relativePath ?? L10n.text("image.none"))
                    .sourceLeafFont(.caption, design: .monospaced)
                    .lineLimit(1)
                Spacer()
                Button { zoomScale = max(0.1, zoomScale / 1.2) } label: { Image(systemName: "minus.magnifyingglass") }
                    .disabled(zoomScale <= 0.1)
                    .help(L10n.text("preview.zoomOut"))
                Text("\(Int((zoomScale * 100).rounded()))%")
                    .sourceLeafFont(.caption, design: .monospaced)
                    .frame(minWidth: 42)
                Button { zoomScale = min(8, zoomScale * 1.2) } label: { Image(systemName: "plus.magnifyingglass") }
                    .disabled(zoomScale >= 8)
                    .help(L10n.text("preview.zoomIn"))
                Button { zoomScale = 1 } label: { Image(systemName: "arrow.counterclockwise") }
                    .help(L10n.text("preview.actualSize"))
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.bar)

            if let url = model.selectedImageFile?.url {
                ZoomableImagePreview(url: url, zoomScale: $zoomScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(L10n.text("image.none"), systemImage: "photo")
            }
        }
    }
}

struct ZoomableImagePreview: NSViewRepresentable {
    let url: URL
    @Binding var zoomScale: Double

    func makeNSView(context: Context) -> ZoomableImageScrollView {
        let view = ZoomableImageScrollView()
        view.load(url: url)
        view.onScaleChanged = { zoomScale = $0 }
        return view
    }

    func updateNSView(_ view: ZoomableImageScrollView, context: Context) {
        if view.loadedURL != url { view.load(url: url) }
        view.setZoomScale(zoomScale)
    }
}

final class ZoomableImageScrollView: NSScrollView {
    private let imageView = PannableImageView()
    private(set) var loadedURL: URL?
    var onScaleChanged: ((Double) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = true
        backgroundColor = .windowBackgroundColor
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        minMagnification = 0.1
        maxMagnification = 8
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignCenter
        imageView.owner = self
        documentView = imageView
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func load(url: URL) {
        loadedURL = url
        imageView.image = NSImage(contentsOf: url)
        let size = imageView.image?.size ?? NSSize(width: 1, height: 1)
        imageView.frame = NSRect(origin: .zero, size: size)
        magnification = 1
        updateCenteringInsets()
        onScaleChanged?(1)
    }

    func setZoomScale(_ scale: Double) {
        let bounded = min(8, max(0.1, scale))
        if abs(magnification - bounded) > 0.005 { setMagnification(bounded, centeredAt: visibleRect.center) }
        updateCenteringInsets()
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        updateCenteringInsets()
        onScaleChanged?(magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) else {
            super.scrollWheel(with: event)
            return
        }
        let next = Self.zoomedScale(from: magnification, scrollingDeltaY: event.scrollingDeltaY)
        setMagnification(next, centeredAt: convert(event.locationInWindow, from: nil))
        updateCenteringInsets()
        onScaleChanged?(next)
    }

    override func layout() {
        super.layout()
        updateCenteringInsets()
    }

    private func updateCenteringInsets() {
        guard let documentView else { return }
        let scaledWidth = documentView.bounds.width * magnification
        let scaledHeight = documentView.bounds.height * magnification
        contentInsets = NSEdgeInsets(
            top: max(0, (contentSize.height - scaledHeight) / 2),
            left: max(0, (contentSize.width - scaledWidth) / 2),
            bottom: max(0, (contentSize.height - scaledHeight) / 2),
            right: max(0, (contentSize.width - scaledWidth) / 2)
        )
    }

    static func zoomedScale(from scale: Double, scrollingDeltaY: Double) -> Double {
        min(8, max(0.1, scale * pow(1.12, scrollingDeltaY)))
    }
}

private final class PannableImageView: NSImageView {
    weak var owner: NSScrollView?
    private var lastDragPoint: NSPoint?

    override func mouseDown(with event: NSEvent) {
        lastDragPoint = event.locationInWindow
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let owner, let lastDragPoint else { return }
        let point = event.locationInWindow
        let delta = NSPoint(x: point.x - lastDragPoint.x, y: point.y - lastDragPoint.y)
        let clip = owner.contentView
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x - delta.x, y: clip.bounds.origin.y + delta.y))
        owner.reflectScrolledClipView(clip)
        self.lastDragPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        lastDragPoint = nil
        NSCursor.pop()
    }
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}

struct PDFPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var zoomScale = 0.0
    @State private var showsThumbnails = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Button { showsThumbnails.toggle() } label: { Image(systemName: "sidebar.left") }
                    .help(L10n.text("pdf.thumbnails"))
                Button { zoomScale = max(0.1, (zoomScale > 0 ? zoomScale : 1) / 1.2) } label: { Image(systemName: "minus.magnifyingglass") }
                    .help(L10n.text("preview.zoomOut"))
                Text(zoomScale > 0 ? "\(Int((zoomScale * 100).rounded()))%" : L10n.text("pdf.fit"))
                    .sourceLeafFont(.caption, design: .monospaced)
                    .frame(minWidth: 42)
                Button { zoomScale = min(8, (zoomScale > 0 ? zoomScale : 1) * 1.2) } label: { Image(systemName: "plus.magnifyingglass") }
                    .help(L10n.text("preview.zoomIn"))
                Button { zoomScale = 0 } label: { Image(systemName: "arrow.counterclockwise") }
                    .help(L10n.text("pdf.fit"))
                Button {
                    if model.buildRunning { model.cancelCompile() }
                    else { model.compile() }
                } label: {
                    Label(
                        model.buildRunning ? L10n.text("build.stop") : L10n.compile,
                        systemImage: model.buildRunning ? "stop.fill" : "play.fill"
                    )
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(model.buildRunning ? .red : .primary)
                .help(model.buildRunning ? L10n.text("build.stop") : L10n.compile)
                Toggle(isOn: Binding(
                    get: { model.configuration.build.autoBuild },
                    set: {
                        model.configuration.build.autoBuild = $0
                        model.persistConfiguration()
                    }
                )) { Image(systemName: model.configuration.build.autoBuild ? "bolt.fill" : "bolt.slash") }
                    .toggleStyle(.button)
                    .help(model.configuration.build.autoBuild
                        ? L10n.text("build.autoCompileOn")
                        : L10n.text("build.autoCompileOff"))
                if model.pdfPageCount > 0 {
                    Divider().frame(height: 16)
                    Button {
                        model.pdfPageIndex = max(0, model.pdfPageIndex - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.pdfPageIndex == 0)
                    .help(L10n.text("pdf.previousPage"))

                    Text("\(model.pdfPageIndex + 1)/\(model.pdfPageCount)")
                        .sourceLeafFont(.caption, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(String(format: L10n.text("pdf.pageIndicator"), model.pdfPageIndex + 1, model.pdfPageCount))

                    Button {
                        model.pdfPageIndex = min(model.pdfPageCount - 1, model.pdfPageIndex + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.pdfPageIndex >= model.pdfPageCount - 1)
                    .help(L10n.text("pdf.nextPage"))
                }
                if model.syncTeXDocument != nil {
                    Label(L10n.text("synctex.commandClickHint"), systemImage: "cursorarrow.click")
                        .sourceLeafFont(.caption2)
                        .foregroundStyle(.tertiary)
                        .labelStyle(.iconOnly)
                        .help(L10n.text("synctex.commandClickHint"))
                }
                Spacer()
                if model.buildRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L10n.buildPhase(model.buildPhase))
                    }
                    .sourceLeafFont(.caption)
                    .foregroundStyle(.secondary)
                }
                if let succeeded = model.buildSucceeded {
                    Label(
                        succeeded ? L10n.text("status.buildSucceeded") : L10n.text("status.buildFailed"),
                        systemImage: succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(succeeded ? .green : .orange)
                    .sourceLeafFont(.caption)
                }
                Button { model.presentPDFExportPanel() } label: { Image(systemName: "square.and.arrow.down") }
                    .disabled(model.pdfURL == nil)
                    .help(L10n.text("pdf.export"))
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(.bar)

            if let url = model.pdfURL {
                ZStack(alignment: .bottom) {
                    PDFKitView(
                        url: url,
                        selection: $model.pdfSelection,
                        pageIndex: $model.pdfPageIndex,
                        pageCount: $model.pdfPageCount,
                        zoomScale: $zoomScale,
                        showThumbnails: showsThumbnails,
                        navigationTarget: model.pdfNavigationTarget,
                        onCommandClick: model.locatePDFPointInSource
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !model.pdfSelection.isEmpty {
                    HStack {
                        Text(model.pdfSelection)
                            .lineLimit(2)
                            .sourceLeafFont(.caption)
                        Spacer()
                        Button(L10n.text("pdf.sendSelection")) {
                            model.instruction = L10n.text("pdf.selectionInstruction") + "\n\n\(model.pdfSelection)"
                            model.revealPanel(.codex, in: .trailing)
                        }
                    }
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 5)
                    .padding(10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                }
            } else {
                ContentUnavailableView(
                    L10n.text("pdf.none"),
                    systemImage: "doc.richtext",
                    description: Text(L10n.text("pdf.compileHint"))
                )
            }
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL
    @Binding var selection: String
    @Binding var pageIndex: Int
    @Binding var pageCount: Int
    @Binding var zoomScale: Double
    var showThumbnails: Bool
    var navigationTarget: PDFNavigationTarget?
    var onCommandClick: (Int, Double, Double, String?) -> Void

    init(
        url: URL,
        selection: Binding<String>,
        pageIndex: Binding<Int>,
        pageCount: Binding<Int>,
        zoomScale: Binding<Double> = .constant(0),
        showThumbnails: Bool = false,
        navigationTarget: PDFNavigationTarget?,
        onCommandClick: @escaping (Int, Double, Double, String?) -> Void
    ) {
        self.url = url
        _selection = selection
        _pageIndex = pageIndex
        _pageCount = pageCount
        _zoomScale = zoomScale
        self.showThumbnails = showThumbnails
        self.navigationTarget = navigationTarget
        self.onCommandClick = onCommandClick
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, pageIndex: $pageIndex, pageCount: $pageCount, zoomScale: $zoomScale)
    }

    func makeNSView(context: Context) -> PDFPreviewContainerView {
        let view = NavigablePDFView()
        view.autoScales = true
        view.minScaleFactor = 0.1
        view.maxScaleFactor = 8
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.document = PDFDocument(url: url)
        view.onCommandClick = onCommandClick
        view.onScaleChanged = { context.coordinator.scaleChanged(to: $0) }
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: Notification.Name.PDFViewSelectionChanged,
            object: view
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: Notification.Name.PDFViewPageChanged,
            object: view
        )
        context.coordinator.updatePageState(from: view)
        return PDFPreviewContainerView(pdfView: view, showsThumbnails: showThumbnails)
    }

    func updateNSView(_ container: PDFPreviewContainerView, context: Context) {
        let view = container.pdfView
        container.showsThumbnails = showThumbnails
        if zoomScale == 0, !view.autoScales { view.autoScales = true }
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            context.coordinator.updatePageState(from: view)
        }
        view.onCommandClick = onCommandClick
        view.onScaleChanged = { context.coordinator.scaleChanged(to: $0) }
        if zoomScale > 0, abs(view.scaleFactor - zoomScale) > 0.005 {
            view.autoScales = false
            view.scaleFactor = min(view.maxScaleFactor, max(view.minScaleFactor, zoomScale))
        }
        guard let document = view.document, document.pageCount > 0 else { return }
        let requestedIndex = min(max(pageIndex, 0), document.pageCount - 1)
        if let requestedPage = document.page(at: requestedIndex), view.currentPage !== requestedPage {
            view.go(to: requestedPage)
        }
        if let navigationTarget,
           context.coordinator.lastNavigationID != navigationTarget.id,
           let page = document.page(at: navigationTarget.pageIndex) {
            context.coordinator.lastNavigationID = navigationTarget.id
            context.coordinator.highlight(
                target: navigationTarget,
                page: page,
                in: view
            )
        }
    }

    static func dismantleNSView(_ view: PDFPreviewContainerView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding var selection: String
        @Binding var pageIndex: Int
        @Binding var pageCount: Int
        @Binding var zoomScale: Double
        var lastNavigationID: UUID?
        private weak var highlightedPage: PDFPage?
        private var highlightAnnotation: PDFAnnotation?

        init(selection: Binding<String>, pageIndex: Binding<Int>, pageCount: Binding<Int>, zoomScale: Binding<Double>) {
            _selection = selection
            _pageIndex = pageIndex
            _pageCount = pageCount
            _zoomScale = zoomScale
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView else { return }
            selection = view.currentSelection?.string ?? ""
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView else { return }
            updatePageState(from: view)
        }

        func updatePageState(from view: PDFView) {
            guard let document = view.document else {
                pageCount = 0
                pageIndex = 0
                return
            }
            pageCount = document.pageCount
            if let currentPage = view.currentPage {
                pageIndex = document.index(for: currentPage)
            } else {
                pageIndex = 0
            }
        }

        func scaleChanged(to scale: Double) {
            if abs(zoomScale - scale) > 0.005 { zoomScale = scale }
        }

        func highlight(target: PDFNavigationTarget, page: PDFPage, in view: PDFView) {
            if let highlightAnnotation, let highlightedPage {
                highlightedPage.removeAnnotation(highlightAnnotation)
            }
            let pageBounds = page.bounds(for: .mediaBox)
            let point = NSPoint(
                x: target.x,
                y: pageBounds.maxY - target.yFromTop
            )
            let annotation = PDFAnnotation(
                bounds: NSRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18),
                forType: .circle,
                withProperties: nil
            )
            annotation.color = .systemOrange
            annotation.interiorColor = NSColor.systemYellow.withAlphaComponent(0.25)
            page.addAnnotation(annotation)
            highlightedPage = page
            highlightAnnotation = annotation
            view.go(to: PDFDestination(page: page, at: NSPoint(x: point.x, y: point.y + 80)))
        }
    }
}

final class NavigablePDFView: PDFView {
    var onCommandClick: ((Int, Double, Double, String?) -> Void)?
    var onScaleChanged: ((Double) -> Void)?

    static func zoomedScale(from scale: Double, scrollingDeltaY: Double) -> Double {
        min(8, max(0.1, scale * pow(1.12, scrollingDeltaY)))
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) else {
            super.scrollWheel(with: event)
            return
        }
        performControlZoom(with: event)
    }

    func performControlZoom(with event: NSEvent) {
        autoScales = false
        scaleFactor = Self.zoomedScale(from: scaleFactor, scrollingDeltaY: event.scrollingDeltaY)
        onScaleChanged?(scaleFactor)
    }

    static func shouldTriggerSourceLookup(clickCount: Int, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        clickCount >= 2 || modifierFlags.contains(.command)
    }

    override func mouseDown(with event: NSEvent) {
        let shouldLocate = Self.shouldTriggerSourceLookup(
            clickCount: event.clickCount,
            modifierFlags: event.modifierFlags
        )
        guard shouldLocate,
              let document,
              let page = page(for: convert(event.locationInWindow, from: nil), nearest: true) else {
            super.mouseDown(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let pagePoint = convert(viewPoint, to: page)
        let bounds = page.bounds(for: .mediaBox)
        let pageIndex = document.index(for: page)
        let x = pagePoint.x
        let yFromTop = bounds.maxY - pagePoint.y
        super.mouseDown(with: event)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onCommandClick?(pageIndex, x, yFromTop, self.currentSelection?.string)
        }
    }
}

final class PDFPreviewContainerView: NSView {
    let pdfView: NavigablePDFView
    private let thumbnailView = PDFThumbnailView()
    var showsThumbnails: Bool {
        didSet { thumbnailView.isHidden = !showsThumbnails; needsLayout = true }
    }
    private var scrollMonitor: Any?

    init(pdfView: NavigablePDFView, showsThumbnails: Bool) {
        self.pdfView = pdfView
        self.showsThumbnails = showsThumbnails
        super.init(frame: .zero)
        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = NSSize(width: 92, height: 120)
        thumbnailView.isHidden = !showsThumbnails
        addSubview(thumbnailView)
        addSubview(pdfView)
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  event.modifierFlags.contains(.control),
                  event.window === self.window,
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
            return self.handleControlScroll(event) ? nil : event
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    func handleControlScroll(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.control) else { return false }
        pdfView.performControlZoom(with: event)
        return true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func layout() {
        super.layout()
        let sidebarWidth: CGFloat = showsThumbnails ? min(132, max(96, bounds.width * 0.22)) : 0
        thumbnailView.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height)
        pdfView.frame = NSRect(x: sidebarWidth, y: 0, width: max(0, bounds.width - sidebarWidth), height: bounds.height)
        if pdfView.autoScales {
            let scale = pdfView.scaleFactor
            DispatchQueue.main.async { [weak pdfView] in pdfView?.onScaleChanged?(scale) }
        }
    }
}

struct BuildLogPanel: View {
    @EnvironmentObject private var model: AppModel

    private var summary: BuildLogSummary { BuildLogSummary(log: model.buildLog) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(L10n.buildPhase(model.buildPhase), systemImage: phaseSymbol)
                    .foregroundStyle(phaseColor)
                if summary.downloadCount > 0 {
                    Label("\(summary.downloadCount)", systemImage: "arrow.down.circle")
                        .help(L10n.text("build.downloads"))
                }
                if summary.warningCount > 0 {
                    Label("\(summary.warningCount)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(L10n.text("validation.warning"))
                }
                if summary.errorCount > 0 {
                    Label("\(summary.errorCount)", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .help(L10n.text("validation.error"))
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.buildLog, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .disabled(model.buildLog.isEmpty)
                .help(L10n.text("build.copyLog"))
            }
            .sourceLeafFont(.caption)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.bar)

            Divider()

            ScrollView([.vertical, .horizontal]) {
                Text(model.buildLog.isEmpty ? L10n.text("build.noLog") : model.buildLog)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
        }
    }

    private var phaseSymbol: String {
        switch model.buildPhase {
        case .idle: "terminal"
        case .preparingResources: "arrow.down.circle"
        case .typesetting: "text.page"
        case .bibliography: "books.vertical"
        case .renderingPDF: "doc.richtext"
        case .finished: "checkmark.circle.fill"
        }
    }

    private var phaseColor: Color {
        switch model.buildPhase {
        case .finished: .green
        case .preparingResources, .typesetting, .bibliography, .renderingPDF: .accentColor
        case .idle: .secondary
        }
    }
}

struct HistoryPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(model.history) { entry in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.relativePath).sourceLeafFont(.caption, design: .monospaced).bold()
                    Spacer()
                    Text(entry.createdAt, style: .relative).sourceLeafFont(.caption2).foregroundStyle(.secondary)
                }
                Text(entry.instruction).lineLimit(2).sourceLeafFont(.caption)
                HStack(alignment: .top, spacing: 0) {
                    HistoryDiffText(title: L10n.text("diff.original"), text: entry.originalText, color: .red)
                    Divider()
                    HistoryDiffText(title: L10n.text("diff.proposed"), text: entry.replacementText, color: .green)
                }
                .frame(minHeight: 96, maxHeight: 210)
                HStack {
                    Text(entry.providerName).sourceLeafFont(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.text("history.prepareRestore")) { model.prepareRevert(entry) }
                        .buttonStyle(.borderless)
                        .help(L10n.text("history.prepareRestoreHelp"))
                }
            }
            .padding(.vertical, 4)
        }
        .overlay {
            if model.history.isEmpty {
                ContentUnavailableView(L10n.text("history.none"), systemImage: "clock.arrow.circlepath")
            }
        }
    }
}

private struct HistoryDiffText: View {
    let title: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).sourceLeafFont(.caption2, weight: .bold).foregroundStyle(color)
            ScrollView([.vertical, .horizontal]) {
                Text(text)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(7)
        .background(color.opacity(0.06))
        .frame(maxWidth: .infinity)
    }
}

private extension ProjectFile {
    var symbolName: String {
        switch kind {
        case .tex: "doc.plaintext"
        case .bibliography: "books.vertical"
        case .style: "paintbrush"
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .other: "doc"
        }
    }
}
