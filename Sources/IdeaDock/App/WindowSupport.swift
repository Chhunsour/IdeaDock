import AppKit
import SwiftUI

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
@MainActor final class WindowFrameKeeper: NSObject, NSWindowDelegate {
    let key: String
    let defaults: UserDefaults
    var frameToPersist: ((NSWindow) -> NSRect)?
    var onClose: () -> Void = {}
    init(key: String, defaults: UserDefaults = .standard) { self.key = key; self.defaults = defaults }
    func windowDidMove(_ notification: Notification) { save(notification) }
    func windowDidResize(_ notification: Notification) { save(notification) }
    func windowWillClose(_ notification: Notification) { save(notification); onClose() }
    private func save(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        saveFrame(window)
    }
    /// Controllers can persist a resting frame even when the note is represented by an edge tab.
    func saveFrame(_ window: NSWindow, evenIfHidden: Bool = false) {
        guard evenIfHidden || window.isVisible else { return }
        let frame = frameToPersist?(window) ?? window.frame
        guard frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0 else { return }
        defaults.set(NSStringFromRect(frame), forKey: "frame.\(key)")
    }
    func restore(_ window: NSWindow) {
        if let value = defaults.string(forKey: "frame.\(key)") {
            var rect = NSRectFromString(value)
            guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
                  rect.width > 0, rect.height > 0 else { window.center(); return }
            rect.size.width = max(rect.width, window.minSize.width)
            rect.size.height = max(rect.height, window.minSize.height)
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) { window.center(); return }
            if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(rect) }) {
                rect = EdgeDockGeometry.restoredFrame(rect, in: screen.visibleFrame)
            }
            window.setFrame(rect, display: false)
        } else { window.center() }
    }
}
@MainActor func makeCapturePanel(width: CGFloat, height: CGFloat) -> CapturePanel {
    let panel = CapturePanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isFloatingPanel = true; panel.becomesKeyOnlyIfNeeded = false; panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
    panel.hasShadow = true; panel.isMovableByWindowBackground = true; panel.level = .floating
    panel.animationBehavior = .utilityWindow
    return panel
}
