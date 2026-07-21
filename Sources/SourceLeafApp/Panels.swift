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
            if query.isEmpty {
                List {
                    OutlineGroup(model.projectTree, children: \.children) { node in
                        ProjectTreeRow(node: node)
                    }
                }
            } else {
                List(filteredFiles) { file in
                    Button { model.openFile(file) } label: {
                        Label(file.relativePath, systemImage: file.symbolName)
                            .font(file.kind == .tex ? .caption.monospaced() : .caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !model.outline.isEmpty {
                Divider()
                Text(L10n.text("project.outline"))
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                List(model.outline) { item in
                    Button { model.jumpToOutline(item) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "number")
                                .foregroundStyle(.tertiary)
                            Text(item.title)
                            Spacer()
                            Text("\(item.line)").foregroundStyle(.tertiary)
                        }
                        .font(.caption)
                        .padding(.leading, CGFloat(max(0, item.level - 1)) * 9)
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 100)
            }
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
        view?.previewItem = url as NSURL
        return view ?? QLPreviewView(frame: .zero, style: .normal)!
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL)?.filePathURL != url { view.previewItem = url as NSURL }
    }
}

struct PDFPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.compile() } label: {
                    Label(L10n.compile, systemImage: "play.fill")
                }
                .disabled(model.buildRunning)
                Spacer()
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
                    PDFKitView(url: url, selection: $model.pdfSelection)
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

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.document = PDFDocument(url: url)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: Notification.Name.PDFViewSelectionChanged,
            object: view
        )
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding var selection: String
        init(selection: Binding<String>) { _selection = selection }
        @objc func selectionChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView else { return }
            selection = view.currentSelection?.string ?? ""
        }
    }
}

struct BuildLogPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(model.buildLog.isEmpty ? L10n.text("build.noLog") : model.buildLog)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            if !model.buildLog.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.buildLog, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .padding(8)
            }
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
