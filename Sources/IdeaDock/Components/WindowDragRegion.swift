import AppKit
import SwiftUI

/// A native window drag surface that leaves neighboring controls and editors interactive.
struct WindowDragRegion: NSViewRepresentable {
    var label: String = "Drag note"
    var allowsDocking = true

    func makeNSView(context: Context) -> NativeWindowDragRegion {
        let view = NativeWindowDragRegion()
        configure(view)
        return view
    }

    func updateNSView(_ view: NativeWindowDragRegion, context: Context) { configure(view) }

    private func configure(_ view: NativeWindowDragRegion) {
        view.allowsDocking = allowsDocking
        let help = allowsDocking ? "Drag to move this note. Place it near a screen edge or corner to dock. Right-click for docking commands." : "Drag to move quick capture."
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(label)
        view.setAccessibilityHelp(help)
        view.toolTip = help
    }
}

final class NativeWindowDragRegion: NSView {
    var allowsDocking = true
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard allowsDocking else { return }
        let menu = NSMenu(title: "Dock Note")
        let dockItem = NSMenuItem(title: "Dock at Screen Edge", action: nil, keyEquivalent: "")
        let edges = NSMenu(title: "Dock at Screen Edge")
        for edge in DockEdge.allCases {
            let item = NSMenuItem(title: edge.label, action: #selector(dockAtEdge(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = edge.rawValue; edges.addItem(item)
        }
        dockItem.submenu = edges; menu.addItem(dockItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func dockAtEdge(_ item: NSMenuItem) {
        guard let window, let edge = item.representedObject as? String else { return }
        NotificationCenter.default.post(name: .ideaWindowDockRequested, object: window, userInfo: ["edge": edge])
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        NotificationCenter.default.post(name: .ideaWindowDragStarted, object: window)
        NSCursor.closedHand.push()
        defer {
            NSCursor.pop()
            NotificationCenter.default.post(name: .ideaWindowDragFinished, object: window)
        }
        window.performDrag(with: event)
    }
}

extension Notification.Name {
    static let ideaWindowDragStarted = Notification.Name("IdeaDock.windowDragStarted")
    static let ideaWindowDragFinished = Notification.Name("IdeaDock.windowDragFinished")
    static let ideaWindowDockRequested = Notification.Name("IdeaDock.windowDockRequested")
}
