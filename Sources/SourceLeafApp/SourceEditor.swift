import AppKit
import SwiftUI
import SourceLeafCore

struct SourcePanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.selectedFile?.relativePath ?? L10n.text("source.noFile"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if model.selectedRange.length > 0 {
                    Button {
                        model.attachCurrentSelection()
                    } label: {
                        Label(L10n.text("selection.askAI"), systemImage: "sparkles")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("k", modifiers: [.option, .command])
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)

            SourceTextView(
                text: Binding(get: { model.sourceText }, set: { model.sourceChanged($0) }),
                selection: $model.selectedRange,
                showSelectionButton: model.configuration.showSelectionButton,
                onAskAI: model.attachCurrentSelection
            )
        }
    }
}

struct SourceTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var showSelectionButton: Bool
    var onAskAI: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.insertionPointColor = .labelColor
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor,
            .foregroundColor: NSColor.selectedTextColor
        ]
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text
        scrollView.documentView = textView

        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        let askButton = NSButton(title: L10n.text("selection.askAI"), target: context.coordinator, action: #selector(Coordinator.askAI))
        askButton.bezelStyle = .rounded
        askButton.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        askButton.imagePosition = .imageLeading
        askButton.translatesAutoresizingMaskIntoConstraints = false
        askButton.isHidden = true

        container.addSubview(scrollView)
        container.addSubview(askButton)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            askButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            askButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18)
        ])

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.askButton = askButton
        context.coordinator.observeScrollView(scrollView)
        context.coordinator.applyHighlighting()
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            let visible = textView.enclosingScrollView?.contentView.bounds
            textView.string = text
            context.coordinator.applyHighlighting()
            if let visible { textView.enclosingScrollView?.contentView.scroll(to: visible.origin) }
        }
        if textView.selectedRange() != selection, NSMaxRange(selection) <= (textView.string as NSString).length {
            textView.setSelectedRange(selection)
            textView.scrollRangeToVisible(selection)
        }
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        context.coordinator.askButton?.title = L10n.text("selection.askAI")
        context.coordinator.updateAskButton()
        context.coordinator.ruler?.needsDisplay = true
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceTextView
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?
        weak var askButton: NSButton?
        private var highlighting = false

        init(parent: SourceTextView) { self.parent = parent }

        func observeScrollView(_ scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        @objc private func scrollBoundsDidChange(_ notification: Notification) {
            ruler?.needsDisplay = true
        }

        func textDidChange(_ notification: Notification) {
            guard !highlighting, let textView else { return }
            parent.text = textView.string
            applyHighlighting()
            ruler?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            parent.selection = textView.selectedRange()
            updateAskButton()
        }

        @objc func askAI() { parent.onAskAI() }

        func updateAskButton() {
            askButton?.isHidden = !parent.showSelectionButton || (textView?.selectedRange().length ?? 0) == 0
        }

        func applyHighlighting() {
            guard let textView, let storage = textView.textStorage else { return }
            highlighting = true
            let selectedRange = textView.selectedRange()
            let source = textView.string as NSString
            let full = NSRange(location: 0, length: source.length)
            storage.beginEditing()
            storage.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor
            ], range: full)
            apply(#"%.*$"#, color: .systemGreen, storage: storage, source: textView.string, options: [.anchorsMatchLines])
            apply(#"\\[A-Za-z@]+\*?"#, color: .systemBlue, storage: storage, source: textView.string)
            apply(#"\$[^$\n]*\$"#, color: .systemPurple, storage: storage, source: textView.string)
            apply(#"\{[^{}\n]*\}"#, color: .systemOrange, storage: storage, source: textView.string)
            storage.endEditing()
            if NSMaxRange(selectedRange) <= source.length { textView.setSelectedRange(selectedRange) }
            textView.typingAttributes = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
            highlighting = false
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

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        NSColor.textBackgroundColor.setFill()
        rect.fill()

        let visible = textView.enclosingScrollView?.contentView.bounds ?? textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let source = textView.string
        for item in SourceLineMap.visibleLineStarts(in: source, utf16Range: characterRange) {
            guard item.utf16Location < (source as NSString).length else { continue }
            let glyph = layoutManager.glyphIndexForCharacter(at: item.utf16Location)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = fragment.minY - visible.minY + textView.textContainerOrigin.y
            let string = "\(item.line)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let size = string.size(withAttributes: attributes)
            string.draw(at: NSPoint(x: ruleThickness - size.width - 7, y: y + 2), withAttributes: attributes)
        }
    }
}
