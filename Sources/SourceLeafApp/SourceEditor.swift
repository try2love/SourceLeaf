import AppKit
import QuartzCore
import SwiftUI
import SourceLeafCore

enum SourceTextSynchronization {
    static func shouldApplyExternalText(
        incoming: String,
        nativeText: String,
        lastLocallyEmittedText: String?
    ) -> Bool {
        guard incoming != nativeText else { return false }
        // SwiftUI may deliver an older binding value after NSTextView has
        // already accepted another keystroke. Never let that echo replace the
        // newer native buffer; a genuine external edit has no local marker.
        return lastLocallyEmittedText != nativeText
    }
}

struct SourcePanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.selectedFile?.relativePath ?? L10n.text("source.noFile"))
                    .sourceLeafFont(.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if model.hasUnsavedChanges {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                        .help(L10n.text("status.unsaved"))
                }
                Spacer()
                Button {
                    model.saveNow()
                } label: {
                    Label(L10n.text("action.save"), systemImage: "square.and.arrow.down")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!model.canSaveCurrentFile || !model.hasUnsavedChanges)
                .help(L10n.text("action.save"))
                if model.configuration.showSelectionButton {
                    Button {
                        model.attachCurrentSelection()
                    } label: {
                        Label(L10n.text("selection.askAI"), systemImage: "sparkles")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedRange.length == 0)
                    .help(model.selectedRange.length == 0
                        ? L10n.text("selection.selectFirst")
                        : L10n.text("selection.askAI"))
                    .keyboardShortcut("k", modifiers: [.option, .command])
                }
                if model.syncTeXDocument != nil, model.selectedFile?.kind == .tex {
                    Button {
                    model.locateSourceInPDF()
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.text("synctex.showInPDF"))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.bar)

            if model.selectedFile?.kind == .tex {
                LaTeXSourceToolbar()
            }

            SourceTextView(
                text: Binding(get: { model.sourceText }, set: { model.sourceChanged($0) }),
                selection: $model.selectedRange,
                commandRequest: model.pendingLaTeXEdit,
                showSelectionButton: model.configuration.showSelectionButton,
                editorTheme: model.editorTheme,
                editorFontFamily: model.editorFontFamily,
                editorFontSize: model.editorFontSize,
                onAskAI: model.attachCurrentSelection,
                onCommandApplied: model.acknowledgeLaTeXEdit
            )
        }
    }
}

private struct LaTeXSourceToolbar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                Button { NotificationCenter.default.post(name: .sourceLeafShowFind, object: nil) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help(L10n.text("source.findReplace"))

                Divider().frame(height: 17)

                formatButton(.bold, key: "source.format.bold", symbol: "bold")
                formatButton(.italic, key: "source.format.italic", symbol: "italic")
                formatButton(.underline, key: "source.format.underline", symbol: "underline")

                Divider().frame(height: 17)

                Menu {
                    menuButton(.section, key: "source.heading.section")
                    menuButton(.subsection, key: "source.heading.subsection")
                    menuButton(.subsubsection, key: "source.heading.subsubsection")
                    menuButton(.paragraph, key: "source.heading.paragraph")
                } label: {
                    Label(L10n.text("source.toolbar.heading"), systemImage: "textformat.size")
                }

                Menu {
                    menuButton(.tiny, title: "\\tiny")
                    menuButton(.scriptsize, title: "\\scriptsize")
                    menuButton(.footnotesize, title: "\\footnotesize")
                    menuButton(.small, title: "\\small")
                    menuButton(.normalsize, title: "\\normalsize")
                    menuButton(.large, title: "\\large")
                    menuButton(.largeUpper, title: "\\Large")
                    menuButton(.largeAllCaps, title: "\\LARGE")
                    menuButton(.huge, title: "\\huge")
                    menuButton(.hugeUpper, title: "\\Huge")
                } label: {
                    Label(L10n.text("source.toolbar.fontSize"), systemImage: "textformat")
                }

                Menu {
                    menuButton(.inlineMath, key: "source.math.inline")
                    menuButton(.displayMath, key: "source.math.display")
                    menuButton(.equation, key: "source.math.equation")
                    Divider()
                    menuButton(.fraction, key: "source.math.fraction")
                    menuButton(.superscript, key: "source.math.superscript")
                    menuButton(.subscriptText, key: "source.math.subscript")
                } label: {
                    Label(L10n.text("source.toolbar.math"), systemImage: "function")
                }

                Menu {
                    menuButton(.emphasis, key: "source.format.emphasis")
                    menuButton(.itemize, key: "source.insert.itemize")
                    menuButton(.enumerate, key: "source.insert.enumerate")
                    menuButton(.table, key: "source.insert.table")
                    menuButton(.figure, key: "source.insert.figure")
                    Divider()
                    menuButton(.cite, key: "source.insert.cite")
                    menuButton(.reference, key: "source.insert.reference")
                    menuButton(.label, key: "source.insert.label")
                    menuButton(.url, key: "source.insert.url")
                } label: {
                    Label(L10n.text("source.toolbar.insert"), systemImage: "plus")
                }
            }
            .font(.system(size: 11 * model.interfaceFontScale))
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func formatButton(_ command: LaTeXEditCommand, key: String, symbol: String) -> some View {
        Button { model.performLaTeXEdit(command) } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .help(L10n.text(key))
        .accessibilityLabel(L10n.text(key))
    }

    private func menuButton(_ command: LaTeXEditCommand, key: String) -> some View {
        Button(L10n.text(key)) { model.performLaTeXEdit(command) }
    }

    private func menuButton(_ command: LaTeXEditCommand, title: String) -> some View {
        Button(title) { model.performLaTeXEdit(command) }
    }
}

struct SourceTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var commandRequest: LaTeXEditRequest? = nil
    var showSelectionButton: Bool
    var editorTheme: EditorTheme = .system
    var editorFontFamily: String = EditorFontCatalog.systemMonospaced
    var editorFontSize: Double = 13
    var onAskAI: () -> Void
    var onCommandApplied: (UUID) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else {
            assertionFailure("NSTextView.scrollableTextView() did not provide a text view")
            return NSView()
        }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        let palette = SourceEditorPalette(theme: editorTheme, appearance: textView.effectiveAppearance)
        let container = SourceEditorContainerView(
            scrollView: scrollView,
            textView: textView,
            backgroundColor: palette.background
        )
        scrollView.drawsBackground = true
        scrollView.backgroundColor = palette.background
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = palette.background
        let editorFont = EditorFontCatalog.font(family: editorFontFamily, size: editorFontSize)
        textView.font = editorFont
        textView.textColor = palette.text
        textView.backgroundColor = palette.background
        textView.drawsBackground = true
        textView.insertionPointColor = palette.caret
        textView.selectedTextAttributes = [
            .backgroundColor: palette.selectionBackground,
            .foregroundColor: palette.selectionText
        ]
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: max(scrollView.contentSize.width, 1), height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text

        let ruler = LineNumberRulerView(textView: textView)
        ruler.backgroundColor = palette.gutterBackground
        ruler.numberColor = palette.gutterText
        ruler.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalRuler = false
        scrollView.rulersVisible = false

        let glyphOverlay = SourceGlyphOverlayView(textView: textView, palette: palette)
        container.glyphOverlay = glyphOverlay

        container.addSubview(ruler)
        container.addSubview(scrollView)
        container.addSubview(glyphOverlay, positioned: .above, relativeTo: scrollView)
        NSLayoutConstraint.activate([
            ruler.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            ruler.topAnchor.constraint(equalTo: container.topAnchor),
            ruler.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ruler.widthAnchor.constraint(equalToConstant: 44),
            scrollView.leadingAnchor.constraint(equalTo: ruler.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.glyphOverlay = glyphOverlay
        context.coordinator.observeScrollView(scrollView)
        glyphOverlay.synchronizeFrame()
        context.coordinator.layoutEditor()
        context.coordinator.applyHighlighting()
        context.coordinator.scheduleInitialHighlighting()
        context.coordinator.applyPendingCommand(commandRequest)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        var requiresFullRefresh = false
        if textView.string == text {
            context.coordinator.lastLocallyEmittedText = nil
        } else if SourceTextSynchronization.shouldApplyExternalText(
            incoming: text,
            nativeText: textView.string,
            lastLocallyEmittedText: context.coordinator.lastLocallyEmittedText
        ) {
            let visible = textView.enclosingScrollView?.contentView.bounds
            let selectedRange = textView.selectedRange()
            textView.string = text
            context.coordinator.lastLocallyEmittedText = nil
            context.coordinator.applyHighlighting()
            if let visible { textView.enclosingScrollView?.contentView.scroll(to: visible.origin) }
            let length = (text as NSString).length
            let restored = NSRange(location: min(selectedRange.location, length), length: 0)
            textView.setSelectedRange(restored)
            requiresFullRefresh = true
        }
        if textView.selectedRange() == selection {
            context.coordinator.lastLocallyEmittedSelection = nil
        } else if context.coordinator.lastLocallyEmittedSelection != textView.selectedRange(),
                  NSMaxRange(selection) <= (textView.string as NSString).length {
            textView.setSelectedRange(selection)
            textView.scrollRangeToVisible(selection)
            context.coordinator.lastLocallyEmittedSelection = nil
        }
        context.coordinator.applyPendingCommand(commandRequest)
        if context.coordinator.appliedStyleSignature != nil,
           context.coordinator.appliedStyleSignature != context.coordinator.currentStyleSignature {
            context.coordinator.applyHighlighting()
            requiresFullRefresh = true
        }
        // A drag selection publishes dozens of binding updates per second. The
        // NSTextView has already updated its selection and layout at this point;
        // forcing TextKit to lay out the whole document again makes the painted
        // selection trail behind the pointer on large files.
        if requiresFullRefresh {
            context.coordinator.layoutEditor()
            context.coordinator.invalidateVisibleEditor()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceTextView
        var textView: NSTextView?
        weak var ruler: LineNumberRulerView?
        weak var glyphOverlay: SourceGlyphOverlayView?
        private var highlighting = false
        private(set) var appliedStyleSignature: String?
        private var lastAppliedCommandID: UUID?
        private var resettingHorizontalScroll = false
        private var completedWindowHighlight = false
        private var selectionSyncTimer: Timer?
        private var highlightTimer: Timer?
        var lastLocallyEmittedText: String?
        var lastLocallyEmittedSelection: NSRange?

        var currentStyleSignature: String {
            let appearance = textView?.effectiveAppearance.name.rawValue ?? "none"
            return "\(parent.editorTheme.rawValue)|\(parent.editorFontFamily)|\(parent.editorFontSize)|\(appearance)"
        }

        init(parent: SourceTextView) { self.parent = parent }

        func observeScrollView(_ scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(showFindAndReplace),
                name: .sourceLeafShowFind,
                object: nil
            )
        }

        @objc private func showFindAndReplace() {
            guard let textView, textView.window?.isKeyWindow == true else { return }
            textView.window?.makeFirstResponder(textView)
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showReplaceInterface.rawValue
            textView.performFindPanelAction(item)
        }

        @objc private func scrollBoundsDidChange(_ notification: Notification) {
            if !resettingHorizontalScroll,
               let clipView = notification.object as? NSClipView,
               abs(clipView.bounds.origin.x) > 0.5 {
                resettingHorizontalScroll = true
                clipView.scroll(to: NSPoint(x: 0, y: clipView.bounds.origin.y))
                clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
                resettingHorizontalScroll = false
            }
            ruler?.scrollPositionDidChange()
            glyphOverlay?.synchronizeFrame()
            glyphOverlay?.needsDisplay = true
        }

        func textDidChange(_ notification: Notification) {
            guard !highlighting, let textView else { return }
            lastLocallyEmittedText = textView.string
            lastLocallyEmittedSelection = textView.selectedRange()
            parent.text = textView.string
            highlightTimer?.invalidate()
            let timer = Timer(timeInterval: 0.08, target: self, selector: #selector(applyDeferredHighlighting), userInfo: nil, repeats: false)
            highlightTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            ruler?.needsDisplay = true
            glyphOverlay?.restartCaretBlink()
            glyphOverlay?.needsDisplay = true
        }

        @objc private func applyDeferredHighlighting() {
            applyHighlighting()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            lastLocallyEmittedSelection = textView.selectedRange()
            // Keep AppKit's native interaction immediate, but coalesce the
            // higher-level SwiftUI binding while a pointer drag is in flight.
            selectionSyncTimer?.invalidate()
            let timer = Timer(timeInterval: 0.05, target: self, selector: #selector(commitSelectionToBinding), userInfo: nil, repeats: false)
            selectionSyncTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            glyphOverlay?.selectionDidChange()
        }

        @objc private func commitSelectionToBinding() {
            guard let textView else { return }
            let range = textView.selectedRange()
            lastLocallyEmittedSelection = range
            if parent.selection != range { parent.selection = range }
        }

        @objc func askAI() {
            selectionSyncTimer?.invalidate()
            commitSelectionToBinding()
            parent.onAskAI()
        }

        func applyPendingCommand(_ request: LaTeXEditRequest?) {
            guard let request, request.id != lastAppliedCommandID else { return }
            lastAppliedCommandID = request.id
            executePendingCommand(request, attempt: 0)
        }

        private func executePendingCommand(_ request: LaTeXEditRequest, attempt: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.05)) { [self] in
                guard let textView = textView else { return }
                guard textView.window != nil else {
                    if attempt < 20 { self.executePendingCommand(request, attempt: attempt + 1) }
                    return
                }
                let edit = LaTeXSourceFormatter.edit(
                    command: request.command,
                    source: textView.string,
                    selection: textView.selectedRange()
                )
                let originalSelection = textView.selectedRange()
                let undoManager = textView.undoManager
                undoManager?.beginUndoGrouping()
                undoManager?.registerUndo(withTarget: self) { target in
                    MainActor.assumeIsolated {
                        target.restoreSelection(originalSelection, opposite: edit.resultingSelection)
                    }
                }
                textView.insertText(edit.replacement, replacementRange: edit.replacementRange)
                textView.setSelectedRange(edit.resultingSelection)
                undoManager?.endUndoGrouping()
                textView.scrollRangeToVisible(edit.resultingSelection)
                self.parent.selection = edit.resultingSelection
                self.glyphOverlay?.needsDisplay = true
                self.parent.onCommandApplied(request.id)
            }
        }

        private func restoreSelection(_ requested: NSRange, opposite: NSRange) {
            guard let textView else { return }
            let length = (textView.string as NSString).length
            let range = NSRange(
                location: min(max(0, requested.location), length),
                length: min(max(0, requested.length), max(0, length - min(max(0, requested.location), length)))
            )
            textView.setSelectedRange(range)
            parent.selection = range
            textView.scrollRangeToVisible(range)
            textView.undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.restoreSelection(opposite, opposite: requested)
                }
            }
            glyphOverlay?.selectionDidChange()
        }

        func scheduleInitialHighlighting(attempt: Int = 0) {
            guard !completedWindowHighlight else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, !self.completedWindowHighlight else { return }
                guard let textView = self.textView, let window = textView.window else {
                    if attempt < 40 { self.scheduleInitialHighlighting(attempt: attempt + 1) }
                    return
                }
                // SwiftUI performs one more representable/layout transaction
                // after the view first acquires a window. Commit TextStorage
                // attributes after that transaction so the window compositor
                // keeps the glyph layer.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak window] in
                    guard let self, let window, window === self.textView?.window else { return }
                    self.applyHighlighting()
                    self.completedWindowHighlight = true
                    self.invalidateVisibleEditor()
                    var ancestor = self.textView?.superview
                    while let view = ancestor {
                        view.needsDisplay = true
                        ancestor = view.superview
                    }
                    window.contentView?.displayIfNeeded()
                    window.displayIfNeeded()
                }
            }
        }

        func applyHighlighting() {
            guard let textView, let storage = textView.textStorage else { return }
            highlighting = true
            let appearance = textView.effectiveAppearance
            let palette = SourceEditorPalette(theme: parent.editorTheme, appearance: appearance)
            let editorFont = EditorFontCatalog.font(
                family: parent.editorFontFamily,
                size: parent.editorFontSize
            )
            let selectedRange = textView.selectedRange()
            let source = textView.string as NSString
            let full = NSRange(location: 0, length: source.length)
            textView.textColor = palette.text
            textView.backgroundColor = palette.background
            textView.font = editorFont
            if let scrollView = textView.enclosingScrollView {
                scrollView.drawsBackground = true
                scrollView.backgroundColor = palette.background
                scrollView.contentView.drawsBackground = true
                scrollView.contentView.backgroundColor = palette.background
                (scrollView.superview as? SourceEditorContainerView)?.backgroundColor = palette.background
            }
            ruler?.backgroundColor = palette.gutterBackground
            ruler?.numberColor = palette.gutterText
            storage.beginEditing()
            storage.setAttributes([
                .font: editorFont,
                .foregroundColor: palette.text
            ], range: full)
            apply(#"\[[^\]\n]*\]"#, color: palette.optionalArgument, storage: storage, source: textView.string)
            apply(#"\\[A-Za-z@]+\*?"#, color: palette.command, storage: storage, source: textView.string)
            apply(#"\$[^$\n]*\$"#, color: palette.math, storage: storage, source: textView.string)
            apply(#"[{}]"#, color: palette.brace, storage: storage, source: textView.string)
            apply(#"(?<!\\)%.*$"#, color: palette.comment, storage: storage, source: textView.string, options: [.anchorsMatchLines])
            storage.endEditing()
            if NSMaxRange(selectedRange) <= source.length { textView.setSelectedRange(selectedRange) }
            textView.typingAttributes = [
                .font: editorFont,
                .foregroundColor: palette.text
            ]
            textView.insertionPointColor = palette.caret
            textView.selectedTextAttributes = [
                .backgroundColor: palette.selectionBackground,
                .foregroundColor: palette.selectionText
            ]
            appliedStyleSignature = currentStyleSignature
            glyphOverlay?.palette = palette
            textView.layoutManager?.invalidateDisplay(forCharacterRange: full)
            if let textContainer = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: textContainer)
            }
            textView.needsDisplay = true
            glyphOverlay?.synchronizeFrame()
            glyphOverlay?.needsDisplay = true
            highlighting = false
        }

        func invalidateVisibleEditor() {
            guard let textView else { return }
            textView.isHidden = false
            textView.alphaValue = 1
            textView.setNeedsDisplay(textView.visibleRect)
            textView.enclosingScrollView?.contentView.needsDisplay = true
            ruler?.needsDisplay = true
            glyphOverlay?.synchronizeFrame()
            glyphOverlay?.needsDisplay = true
        }

        func layoutEditor() {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let width = max(scrollView.contentSize.width, 1)
            guard width.isFinite else { return }
            if abs(textView.frame.width - width) > 0.5 {
                textView.setFrameSize(NSSize(width: width, height: max(textView.frame.height, 1)))
            }
            textView.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            if let textContainer = textView.textContainer {
                textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
                textContainer.widthTracksTextView = true
                textView.layoutManager?.ensureLayout(for: textContainer)
            }
            textView.setNeedsDisplay(textView.visibleRect)
            glyphOverlay?.synchronizeFrame()
        }

        private func apply(
            _ pattern: String,
            color: NSColor,
            storage: NSTextStorage,
            source: String,
            options: NSRegularExpression.Options = []
        ) {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let range = NSRange(location: 0, length: (source as NSString).length)
            for match in expression.matches(in: source, range: range) {
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
    }
}

final class SourceGlyphOverlayView: NSView {
    weak var textView: NSTextView?
    var palette: SourceEditorPalette
    private(set) var lastSelectionRectCount = 0
    private(set) var lastCaretRect: NSRect?
    private(set) var lastPaintedSelection = NSRange(location: NSNotFound, length: 0)
    private let caretLayer = CALayer()
    var caretBlinkAnimationActive: Bool { caretLayer.animation(forKey: "SourceLeafCaretBlink") != nil }

    init(textView: NSTextView, palette: SourceEditorPalette) {
        self.textView = textView
        self.palette = palette
        super.init(frame: .zero)
        autoresizingMask = []
        wantsLayer = true
        layer?.isGeometryFlipped = true
        caretLayer.isHidden = true
        caretLayer.actions = ["bounds": NSNull(), "position": NSNull(), "backgroundColor": NSNull(), "hidden": NSNull()]
        layer?.addSublayer(caretLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            caretLayer.removeAllAnimations()
            caretLayer.isHidden = true
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func selectionDidChange() {
        restartCaretBlink()
        needsDisplay = true
        lastPaintedSelection = textView?.selectedRange() ?? NSRange(location: NSNotFound, length: 0)
    }

    func restartCaretBlink() {
        caretLayer.removeAnimation(forKey: "SourceLeafCaretBlink")
        if !caretLayer.isHidden { installCaretBlinkAnimation() }
    }

    func synchronizeFrame() {
        guard let clipView = textView?.enclosingScrollView?.contentView,
              let superview else { return }
        frame = clipView.convert(clipView.bounds, to: superview)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let scrollView = textView.enclosingScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let visible = scrollView.contentView.bounds
        let origin = NSPoint(
            x: textView.textContainerOrigin.x - visible.minX,
            y: textView.textContainerOrigin.y - visible.minY
        )
        lastSelectionRectCount = 0
        lastCaretRect = nil
        caretLayer.isHidden = true
        caretLayer.removeAnimation(forKey: "SourceLeafCaretBlink")
        let selectedRange = textView.selectedRange()
        lastPaintedSelection = selectedRange
        // Selection and find-result painting belong to NSTextView. Keeping the
        // overlay out of the pointer-tracking path makes drag selection native
        // and prevents it from covering the system find indicators.
        if selectedRange.length == 0,
           textView.window?.firstResponder === textView,
           let caret = caretRect(
               at: selectedRange.location,
               textView: textView,
               layoutManager: layoutManager,
               textContainer: textContainer,
               origin: origin
           ) {
            lastCaretRect = caret
            caretLayer.frame = caret
            caretLayer.backgroundColor = palette.caret.cgColor
            caretLayer.isHidden = false
            installCaretBlinkAnimation()
        }
    }

    private func installCaretBlinkAnimation() {
        guard caretLayer.animation(forKey: "SourceLeafCaretBlink") == nil else { return }
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1, 1, 0, 0]
        animation.keyTimes = [0, 0.49, 0.5, 1]
        animation.duration = 1.06
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        caretLayer.add(animation, forKey: "SourceLeafCaretBlink")
    }

    private func caretRect(
        at characterIndex: Int,
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        origin: NSPoint
    ) -> NSRect? {
        let length = (textView.string as NSString).length
        if characterIndex < length {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            guard glyphRect.height > 0 else { return nil }
            return NSRect(x: glyphRect.minX + origin.x, y: glyphRect.minY + origin.y, width: 2, height: glyphRect.height)
        }
        let extra = layoutManager.extraLineFragmentRect
        guard extra.height > 0 else { return nil }
        return NSRect(x: extra.minX + origin.x, y: extra.minY + origin.y, width: 2, height: extra.height)
    }
}

extension Notification.Name {
    static let sourceLeafShowFind = Notification.Name("SourceLeaf.showFindAndReplace")
}

final class SourceEditorContainerView: NSView {
    private let editorScrollView: NSScrollView
    private let editorTextView: NSTextView
    weak var glyphOverlay: SourceGlyphOverlayView?
    var backgroundColor: NSColor {
        didSet {
            layer?.backgroundColor = backgroundColor.cgColor
            needsDisplay = true
        }
    }

    init(scrollView: NSScrollView, textView: NSTextView, backgroundColor: NSColor) {
        editorScrollView = scrollView
        editorTextView = textView
        self.backgroundColor = backgroundColor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let width = max(editorScrollView.contentSize.width, 1)
        guard width.isFinite else { return }
        if abs(editorTextView.frame.width - width) > 0.5 {
            editorTextView.setFrameSize(NSSize(width: width, height: max(editorTextView.frame.height, 1)))
        }
        editorTextView.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        if let textContainer = editorTextView.textContainer {
            textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textContainer.widthTracksTextView = true
            editorTextView.layoutManager?.ensureLayout(for: textContainer)
        }
        glyphOverlay?.synchronizeFrame()
        glyphOverlay?.needsDisplay = true
        editorTextView.setNeedsDisplay(editorTextView.visibleRect)
    }
}

struct SourceEditorPalette {
    let text: NSColor
    let background: NSColor
    let command: NSColor
    let comment: NSColor
    let optionalArgument: NSColor
    let math: NSColor
    let brace: NSColor
    let selectionBackground: NSColor
    let selectionText: NSColor
    let caret: NSColor
    let gutterBackground: NSColor
    let gutterText: NSColor

    init(theme: EditorTheme, appearance: NSAppearance) {
        let dark = theme.isDark(for: appearance)
        if dark {
            text = NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1)
            background = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1)
            command = NSColor(srgbRed: 0.38, green: 0.68, blue: 1.00, alpha: 1)
            comment = NSColor(srgbRed: 0.35, green: 0.78, blue: 0.43, alpha: 1)
            optionalArgument = NSColor(srgbRed: 0.38, green: 0.78, blue: 0.82, alpha: 1)
            math = NSColor(srgbRed: 0.80, green: 0.55, blue: 0.95, alpha: 1)
            brace = NSColor(srgbRed: 1.00, green: 0.64, blue: 0.27, alpha: 1)
            selectionBackground = NSColor(srgbRed: 0.18, green: 0.42, blue: 0.72, alpha: 1)
            selectionText = text
            caret = NSColor(srgbRed: 0.98, green: 0.76, blue: 0.25, alpha: 1)
            gutterBackground = NSColor(srgbRed: 0.075, green: 0.085, blue: 0.10, alpha: 1)
            gutterText = NSColor(srgbRed: 0.57, green: 0.60, blue: 0.66, alpha: 1)
        } else {
            text = NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1)
            background = NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1)
            command = NSColor(srgbRed: 0.05, green: 0.18, blue: 0.95, alpha: 1)
            comment = NSColor(srgbRed: 0.30, green: 0.61, blue: 0.47, alpha: 1)
            optionalArgument = NSColor(srgbRed: 0.19, green: 0.55, blue: 0.62, alpha: 1)
            math = NSColor(srgbRed: 0.55, green: 0.20, blue: 0.72, alpha: 1)
            brace = NSColor(srgbRed: 0.92, green: 0.42, blue: 0.00, alpha: 1)
            selectionBackground = NSColor(srgbRed: 0.70, green: 0.83, blue: 0.97, alpha: 1)
            selectionText = text
            caret = NSColor(srgbRed: 0.05, green: 0.18, blue: 0.95, alpha: 1)
            gutterBackground = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
            gutterText = NSColor(srgbRed: 0.36, green: 0.37, blue: 0.40, alpha: 1)
        }
    }
}

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    private(set) var lastDrawnLines: [Int] = []
    private(set) var scrollChangeCount = 0
    var backgroundColor = NSColor.textBackgroundColor
    var numberColor = NSColor.secondaryLabelColor

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    func scrollPositionDidChange() {
        scrollChangeCount += 1
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        backgroundColor.setFill()
        rect.fill()

        let visible = textView.enclosingScrollView?.contentView.bounds ?? textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let source = textView.string
        let visibleLines = SourceLineMap.visibleLineStarts(in: source, utf16Range: characterRange)
        lastDrawnLines = visibleLines.map(\.line)
        for item in visibleLines {
            guard item.utf16Location < (source as NSString).length else { continue }
            let glyph = layoutManager.glyphIndexForCharacter(at: item.utf16Location)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = fragment.minY - visible.minY + textView.textContainerOrigin.y
            let string = "\(item.line)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: numberColor
            ]
            let size = string.size(withAttributes: attributes)
            string.draw(at: NSPoint(x: ruleThickness - size.width - 7, y: y + 2), withAttributes: attributes)
        }
    }
}
