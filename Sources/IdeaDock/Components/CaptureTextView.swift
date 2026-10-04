import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CaptureTextView: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onEscape: () -> Void = {}
    var onPasteAttachments: () -> Void = {}
    var submitWithReturn: Bool = true
    var focusToken: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false

        let input = CaptureInputTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        input.delegate = context.coordinator
        input.isEditable = true
        input.isSelectable = true
        input.isRichText = false
        input.importsGraphics = false
        input.allowsUndo = true
        input.drawsBackground = false
        input.font = .systemFont(ofSize: 16)
        input.textColor = .labelColor
        input.insertionPointColor = .labelColor
        input.textContainerInset = NSSize(width: 5, height: 8)
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.minSize = NSSize(width: 0, height: 0)
        input.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        input.autoresizingMask = [.width]
        input.textContainer?.widthTracksTextView = true
        input.textContainer?.heightTracksTextView = false
        input.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        input.setAccessibilityLabel("Capture input")
        input.string = text
        scrollView.documentView = input
        configure(input, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let input = scrollView.documentView as? CaptureInputTextView else { return }
        if input.string != text {
            let selection = input.selectedRange()
            input.string = text
            let count = (text as NSString).length
            let location = min(selection.location, count)
            input.setSelectedRange(NSRange(location: location, length: min(selection.length, count - location)))
        }
        configure(input, coordinator: context.coordinator)
    }

    private func configure(_ input: CaptureInputTextView, coordinator: Coordinator) {
        input.onSubmit = onSubmit
        input.onEscape = onEscape
        input.onPasteAttachments = onPasteAttachments
        input.submitWithReturn = submitWithReturn
        if coordinator.lastFocusToken != focusToken {
            coordinator.lastFocusToken = focusToken
            input.requestFocus()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CaptureTextView
        var lastFocusToken: Int?
        init(_ parent: CaptureTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let input = notification.object as? NSTextView else { return }
            parent.text = input.string
        }
    }
}

private final class CaptureInputTextView: NSTextView {
    var onSubmit: () -> Void = {}
    var onEscape: () -> Void = {}
    var onPasteAttachments: () -> Void = {}
    var submitWithReturn = true
    private var pendingFocus = false

    func requestFocus() {
        pendingFocus = true
        focusWhenAttached()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusWhenAttached()
    }

    private func focusWhenAttached() {
        guard pendingFocus, window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingFocus, let window = self.window else { return }
            if window.makeFirstResponder(self) { self.pendingFocus = false }
        }
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !hasMarkedText(), event.keyCode == 36 || event.keyCode == 76 {
            if modifiers.contains(.command) || (submitWithReturn && !modifiers.contains(.shift)) {
                onSubmit()
                return
            }
        }
        if event.keyCode == 53, !hasMarkedText() {
            onEscape()
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        let types = NSPasteboard.general.types ?? []
        let hasAttachment = types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) ||
            types.contains { UTType($0.rawValue)?.conforms(to: .image) == true }
        if hasAttachment { onPasteAttachments() }
        else { super.paste(sender) }
    }
}
