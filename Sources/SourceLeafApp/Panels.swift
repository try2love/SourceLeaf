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
                OutlineGroup(model.projectTree, children: \.children) { node in
                    ProjectTreeRow(node: node)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))
        } else {
            List(filteredFiles) { file in
                Button { model.openFile(file) } label: {
                    Label(file.relativePath, systemImage: file.symbolName)
                        .font(file.kind == .tex ? .caption.monospaced() : .caption)
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
            .font(.caption.weight(.semibold))
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
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("\(node.item.line)").foregroundStyle(.tertiary)
                        }
                        .font(.caption)
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

private struct ProjectTreeRow: View {
    @EnvironmentObject private var model: AppModel
    let node: ProjectTreeNode

    var body: some View {
        if let file = node.file {
            Button { model.openFile(file) } label: {
                Label(node.name, systemImage: file.symbolName)
                    .font(file.kind == .tex ? .caption.monospaced() : .caption)
            }
            .buttonStyle(.plain)
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
                .font(.caption)
        }
    }
}

struct ImagePanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "photo")
                Text(model.selectedImageFile?.relativePath ?? L10n.text("image.none"))
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.bar)

            if let url = model.selectedImageFile?.url {
                QuickLookPreview(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(L10n.text("image.none"), systemImage: "photo")
            }
        }
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)
        view?.autostarts = true
        view?.shouldCloseWithWindow = false
        view?.previewItem = url as NSURL
        return view ?? QLPreviewView(frame: .zero, style: .normal)!
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL)?.filePathURL != url { view.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: Void) {
        view.autostarts = false
        view.previewItem = nil
        view.close()
    }
}

struct PDFPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
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

                    Text(String(format: L10n.text("pdf.pageIndicator"), model.pdfPageIndex + 1, model.pdfPageCount))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

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
                        .font(.caption2)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let succeeded = model.buildSucceeded {
                    Label(
                        succeeded ? L10n.text("status.buildSucceeded") : L10n.text("status.buildFailed"),
                        systemImage: succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(succeeded ? .green : .orange)
                    .font(.caption)
                }
            }
            .padding(7)
            .background(.bar)

            if let url = model.pdfURL {
                ZStack(alignment: .bottom) {
                    PDFKitView(
                        url: url,
                        selection: $model.pdfSelection,
                        pageIndex: $model.pdfPageIndex,
                        pageCount: $model.pdfPageCount,
                        navigationTarget: model.pdfNavigationTarget,
                        onCommandClick: model.locatePDFPointInSource
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !model.pdfSelection.isEmpty {
                    HStack {
                        Text(model.pdfSelection)
                            .lineLimit(2)
                            .font(.caption)
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
    var navigationTarget: PDFNavigationTarget?
    var onCommandClick: (Int, Double, Double, String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, pageIndex: $pageIndex, pageCount: $pageCount)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = NavigablePDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.document = PDFDocument(url: url)
        view.onCommandClick = onCommandClick
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
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            context.coordinator.updatePageState(from: view)
        }
        if let navigableView = view as? NavigablePDFView {
            navigableView.onCommandClick = onCommandClick
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

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding var selection: String
        @Binding var pageIndex: Int
        @Binding var pageCount: Int
        var lastNavigationID: UUID?
        private weak var highlightedPage: PDFPage?
        private var highlightAnnotation: PDFAnnotation?

        init(selection: Binding<String>, pageIndex: Binding<Int>, pageCount: Binding<Int>) {
            _selection = selection
            _pageIndex = pageIndex
            _pageCount = pageCount
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
            .font(.caption)
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
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(entry.relativePath).font(.caption.monospaced()).bold()
                    Spacer()
                    Text(entry.createdAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
                Text(entry.instruction).lineLimit(2).font(.caption)
                HStack {
                    Text(entry.providerName).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.text("history.prepareRestore")) { model.prepareRevert(entry) }
                        .buttonStyle(.borderless)
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

private extension ProjectFile {
    var symbolName: String {
        switch kind {
        case .tex: "doc.plaintext"
        case .bibliography: "books.vertical"
        case .style: "paintbrush"
        case .image: "photo"
        case .other: "doc"
        }
    }
}
