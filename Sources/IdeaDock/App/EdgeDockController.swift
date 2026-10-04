import AppKit
import QuartzCore

/// Owns presentation only: the original editor remains alive while its window is tucked away.
@MainActor final class EdgeDockController {
    private struct Record: Codable {
        let edge: DockEdge
        let fraction: Double
        let screenID: UInt32?
        let screenFrame: String
        let restingFrame: String
    }
    let window: NSWindow
    private let key: String
    private let defaults: UserDefaults
    private let title: () -> String
    private var placement: DockPlacement?
    private var screenID: UInt32?
    private var lastScreenFrame = NSRect.zero
    private var restingFrame: NSRect
    private var handle: DockHandlePanel?
    private var preview: DockHandlePanel?
    private var observers: [NSObjectProtocol] = []
    private var mouseMonitor: Any?
    private var trackingTimer: Timer?
    private var dragging = false
    private var dragStartFrame = NSRect.zero
    private var movedDuringDrag = false
    private var cancelled = false
    private var transitioning = false
    private var movingInternally = false
    private var invalidated = false
    private var transitionID = 0
    private var pending: DockPlacement?
    private var pendingScreen: NSScreen?
    private var handleDragOrigin: NSPoint?
    private var handleDragFrame: NSRect?

    var isDocked: Bool { placement != nil }
    var isVisible: Bool { window.isVisible || handle?.isVisible == true }
    var frameForPersistence: NSRect? { isDocked || transitioning ? restingFrame : nil }

    init(window: NSWindow, key: String, defaults: UserDefaults, title: @escaping () -> String) {
        self.window = window; self.key = key; self.defaults = defaults; self.title = title
        restingFrame = window.frame
        restoreRecord()
        observe(.ideaWindowDragStarted, object: window) { $0.beginDragging() }
        observe(.ideaWindowDragFinished, object: window) { $0.finishDragging() }
        observers.append(NotificationCenter.default.addObserver(forName: .ideaWindowDockRequested, object: window, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?["edge"] as? String, let edge = DockEdge(rawValue: raw) else { return }
            MainActor.assumeIsolated { self?.dockAtEdge(edge) }
        })
        observe(NSWindow.willMoveNotification, object: window) { controller in
            if NSEvent.pressedMouseButtons & 1 != 0 { controller.beginDragging() }
        }
        observe(NSWindow.didMoveNotification, object: window) { $0.windowMoved() }
        observe(NSWindow.didResizeNotification, object: window) { controller in
            if !controller.isDocked && !controller.transitioning { controller.restingFrame = controller.window.frame }
        }
        observe(NSWindow.willCloseNotification, object: window) { $0.invalidate() }
        observe(NSApplication.didChangeScreenParametersNotification, object: nil) { $0.screenLayoutChanged() }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.dragging else { return }
                if event.type == .keyDown && event.keyCode == 53 { self.cancelled = true; self.finishDragging() }
                else if event.type == .leftMouseUp { self.finishDragging() }
            }
            return event
        }
    }

    private func observe(_ name: Notification.Name, object: Any?, action: @escaping (EdgeDockController) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self, !self.invalidated { action(self) } }
        })
    }

    func show() {
        guard !invalidated else { return }
        if isDocked { window.orderOut(nil); showHandle(animated: false) }
        else { window.orderFrontRegardless() }
    }

    func hide() {
        transitionID += 1; transitioning = false
        endTracking(); preview?.orderOut(nil); handle?.orderOut(nil); window.orderOut(nil)
        movingInternally = true; window.setFrame(restingFrame, display: false); movingInternally = false
        window.alphaValue = preferredOpacity
    }

    /// Keyboard/VoiceOver alternative to placing the note with the mouse.
    func dockAtEdge(_ edge: DockEdge) {
        guard !invalidated, !transitioning, !isDocked, window.isVisible, !window.isMiniaturized, window.attachedSheet == nil else { return }
        let screen = window.screen ?? screenForDrag()
        let visible = screen.visibleFrame
        let center = edge.isVertical ? window.frame.midY : window.frame.midX
        let origin = edge.isVertical ? visible.minY : visible.minX
        let length = edge.isVertical ? visible.height : visible.width
        let handleLength = min(84, length)
        let fraction = length > handleLength ? min(1, max(0, (center - origin - handleLength / 2) / (length - handleLength))) : 0.5
        endTracking()
        dock(DockPlacement(edge: edge, fraction: fraction), on: screen)
    }

    func reveal() {
        guard !invalidated else { return }
        if !isDocked {
            window.makeKeyAndOrderFront(nil)
            if !(window is NSPanel) { NSApp.activate(ignoringOtherApps: true) }
            return
        }
        let edge = placement!.edge
        let screen = dockScreen()
        restingFrame = EdgeDockGeometry.restoredFrame(restingFrame, in: screen.visibleFrame)
        placement = nil; defaults.removeObject(forKey: storageKey)
        preview?.orderOut(nil)
        transitionID += 1; let token = transitionID; transitioning = true
        movingInternally = true
        window.setFrame(EdgeDockGeometry.translatedFrame(restingFrame, toward: edge, distance: reduceMotion ? 0 : 26), display: false)
        window.alphaValue = reduceMotion ? preferredOpacity : 0
        movingInternally = false
        window.makeKeyAndOrderFront(nil)
        if !(window is NSPanel) { NSApp.activate(ignoringOtherApps: true) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(restingFrame, display: true)
            window.animator().alphaValue = preferredOpacity
            handle?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.transitionID == token else { return }
                self.handle?.orderOut(nil); self.transitioning = false
                self.persistRestingFrame()
            }
        }
    }

    func synchronizePreferences() {
        guard !invalidated else { return }
        for panel in [handle, preview].compactMap({ $0 }) {
            panel.level = window.level
            panel.collectionBehavior = window.collectionBehavior
            panel.appearance = window.appearance ?? NSApp.appearance
        }
        if !transitioning { handle?.alphaValue = preferredOpacity }
    }

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true; transitionID += 1
        endTracking()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }; mouseMonitor = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers = []
        preview?.orderOut(nil); handle?.orderOut(nil)
        preview = nil; handle = nil
    }

    private var storageKey: String { "edgeDock.\(key)" }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var preferredOpacity: CGFloat { CGFloat(defaults.object(forKey: "IdeaDock.opacity") as? Double ?? 0.97) }

    private func beginDragging() {
        guard !invalidated, !isDocked, !transitioning, !movingInternally, !window.inLiveResize, window.attachedSheet == nil else { return }
        guard !dragging else { return }
        dragging = true; cancelled = false; restingFrame = window.frame
        dragStartFrame = window.frame; movedDuringDrag = false
        let timer = Timer(timeInterval: 0.035, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.dragging else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 { self.finishDragging() }
                else { self.updatePreview() }
            }
        }
        trackingTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    private func windowMoved() {
        guard !invalidated, !movingInternally, !transitioning, !isDocked, window.isVisible, !window.inLiveResize else { return }
        if dragging || NSEvent.pressedMouseButtons & 1 != 0 {
            beginDragging(); updatePreview()
        } else if !dragging { restingFrame = window.frame }
    }

    private func updatePreview() {
        guard dragging, !cancelled, !transitioning else { return }
        if hypot(window.frame.minX - dragStartFrame.minX, window.frame.minY - dragStartFrame.minY) >= 3 { movedDuringDrag = true }
        guard movedDuringDrag else { preview?.orderOut(nil); return }
        let screen = screenForDrag()
        let candidate = EdgeDockGeometry.candidate(for: window.frame, in: screen.visibleFrame, threshold: pending == nil ? 22 : 32)
        pending = candidate; pendingScreen = screen
        guard let candidate else { preview?.orderOut(nil); return }
        if preview == nil { preview = makeHandlePanel(interactive: false) }
        guard let preview else { return }
        let view = preview.contentView as? DockHandleView
        view?.configure(edge: candidate.edge, preview: true, title: title())
        preview.setFrame(EdgeDockGeometry.handleFrame(for: candidate, in: screen.visibleFrame), display: true)
        preview.alphaValue = 0.66
        preview.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        preview.orderFrontRegardless()
    }

    private func finishDragging() {
        guard dragging else { return }
        // Keep cancellation latched until release: AppKit can keep delivering
        // didMove while the physical mouse button is still down after Escape.
        if cancelled, NSEvent.pressedMouseButtons & 1 != 0 { preview?.orderOut(nil); return }
        // AppKit's performDrag returns immediately and may consume mouse-up.
        // The common-mode timer remains the reliable release signal.
        guard cancelled || NSEvent.pressedMouseButtons & 1 == 0 else { return }
        let wasCancelled = cancelled
        let didMove = movedDuringDrag || hypot(window.frame.minX - dragStartFrame.minX, window.frame.minY - dragStartFrame.minY) >= 3
        let screen = screenForDrag()
        let candidate = EdgeDockGeometry.candidate(for: window.frame, in: screen.visibleFrame, threshold: pending != nil && pendingScreen === screen ? 32 : 22)
        endTracking()
        if !wasCancelled, didMove, let candidate, window.isVisible { dock(candidate, on: screen) }
        else { preview?.orderOut(nil); restingFrame = window.frame }
    }

    private func endTracking() {
        trackingTimer?.invalidate(); trackingTimer = nil
        dragging = false; movedDuringDrag = false; pending = nil; pendingScreen = nil
    }

    private func dock(_ placement: DockPlacement, on screen: NSScreen) {
        guard !invalidated, !transitioning else { return }
        restingFrame = EdgeDockGeometry.restoredFrame(window.frame, in: screen.visibleFrame)
        self.placement = placement; screenID = displayID(screen); lastScreenFrame = screen.visibleFrame
        saveRecord(); persistRestingFrame()
        transitionID += 1; let token = transitionID; transitioning = true
        showHandle(animated: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(EdgeDockGeometry.translatedFrame(restingFrame, toward: placement.edge, distance: reduceMotion ? 0 : 44), display: true)
            window.animator().alphaValue = 0
            preview?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.transitionID == token else { return }
                self.window.orderOut(nil); self.preview?.orderOut(nil)
                self.movingInternally = true; self.window.setFrame(self.restingFrame, display: false); self.movingInternally = false
                self.window.alphaValue = self.preferredOpacity; self.transitioning = false
            }
        }
    }

    private func showHandle(animated: Bool) {
        guard let placement else { return }
        if handle == nil { handle = makeHandlePanel(interactive: true) }
        guard let handle else { return }
        let screen = dockScreen()
        (handle.contentView as? DockHandleView)?.configure(edge: placement.edge, preview: false, title: title())
        let frame = EdgeDockGeometry.handleFrame(for: placement, in: screen.visibleFrame)
        handle.setFrame(frame, display: true); synchronizePreferences()
        handle.alphaValue = animated && !reduceMotion ? 0 : preferredOpacity
        handle.orderFrontRegardless()
        if animated && !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22; context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                handle.animator().alphaValue = preferredOpacity
            }
        }
    }

    private func makeHandlePanel(interactive: Bool) -> DockHandlePanel {
        let panel = DockHandlePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = interactive ? "Docked \(title())" : "Docking preview"
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.ignoresMouseEvents = !interactive; panel.isMovable = false
        panel.level = window.level; panel.collectionBehavior = window.collectionBehavior
        let view = DockHandleView(frame: .zero)
        if interactive {
            view.onClick = { [weak self] in self?.reveal() }
            view.onDragStart = { [weak self] point in self?.startHandleDrag(at: point) }
            view.onDrag = { [weak self] point in self?.moveHandleDrag(to: point) }
            view.onDragEnd = { [weak self] in self?.finishHandleDrag() }
            view.onDragCancel = { [weak self] in
                guard let self else { return }
                self.cancelled = true; self.finishHandleDrag()
            }
        }
        panel.contentView = view
        return panel
    }

    private func startHandleDrag(at point: NSPoint) {
        guard isDocked, !invalidated else { return }
        transitionID += 1; transitioning = false
        let screen = dockScreen()
        restingFrame = EdgeDockGeometry.restoredFrame(restingFrame, in: screen.visibleFrame)
        placement = nil; defaults.removeObject(forKey: storageKey)
        handle?.orderOut(nil); preview?.orderOut(nil)
        // The grab remains near the note's header, so dragging out feels attached to the handle.
        let origin = NSPoint(x: point.x - restingFrame.width * 0.5, y: point.y - restingFrame.height + 28)
        movingInternally = true; window.setFrameOrigin(origin); window.alphaValue = preferredOpacity; movingInternally = false
        window.orderFrontRegardless()
        handleDragOrigin = point; handleDragFrame = window.frame
        beginDragging(); movedDuringDrag = true
    }

    private func moveHandleDrag(to point: NSPoint) {
        guard dragging, !transitioning, !invalidated, let start = handleDragOrigin, let frame = handleDragFrame else { return }
        movingInternally = true
        window.setFrameOrigin(NSPoint(x: frame.minX + point.x - start.x, y: frame.minY + point.y - start.y))
        movingInternally = false; updatePreview()
    }

    private func finishHandleDrag() {
        guard !invalidated else { return }
        handleDragOrigin = nil; handleDragFrame = nil
        finishDragging()
        if !isDocked, window.isVisible { window.makeKeyAndOrderFront(nil); if !(window is NSPanel) { NSApp.activate(ignoringOtherApps: true) } }
    }

    private func screenForDrag() -> NSScreen {
        let pointer = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) { return screen }
        return NSScreen.screens.max { intersectionArea($0.visibleFrame, window.frame) < intersectionArea($1.visibleFrame, window.frame) } ?? NSScreen.main!
    }
    private func dockScreen() -> NSScreen {
        if let screenID, let screen = NSScreen.screens.first(where: { displayID($0) == screenID }) { return screen }
        return NSScreen.screens.max { intersectionArea($0.visibleFrame, lastScreenFrame) < intersectionArea($1.visibleFrame, lastScreenFrame) } ?? NSScreen.main!
    }
    private func intersectionArea(_ a: NSRect, _ b: NSRect) -> CGFloat { let rect = a.intersection(b); return rect.isNull ? 0 : rect.width * rect.height }
    private func displayID(_ screen: NSScreen) -> UInt32? { (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }

    private func screenLayoutChanged() {
        guard isDocked, !invalidated else { return }
        let screen = dockScreen(); screenID = displayID(screen); lastScreenFrame = screen.visibleFrame
        restingFrame = EdgeDockGeometry.restoredFrame(restingFrame, in: screen.visibleFrame)
        movingInternally = true; window.setFrame(restingFrame, display: false); movingInternally = false
        saveRecord(); persistRestingFrame()
        if handle?.isVisible == true { showHandle(animated: false) }
    }

    private func restoreRecord() {
        guard let data = defaults.data(forKey: storageKey), let record = try? JSONDecoder().decode(Record.self, from: data), record.fraction.isFinite else { return }
        var saved = NSRectFromString(record.restingFrame)
        guard saved.width.isFinite, saved.height.isFinite, saved.minX.isFinite, saved.minY.isFinite,
              saved.width > 0, saved.height > 0 else { defaults.removeObject(forKey: storageKey); return }
        // Native layout can report a smaller frame during a size transition.
        // Preserve its docking identity and bring it up to the current minimum.
        saved.size.width = max(saved.width, window.minSize.width)
        saved.size.height = max(saved.height, window.minSize.height)
        screenID = record.screenID; lastScreenFrame = NSRectFromString(record.screenFrame)
        placement = DockPlacement(edge: record.edge, fraction: CGFloat(min(1, max(0, record.fraction))))
        restingFrame = EdgeDockGeometry.restoredFrame(saved, in: dockScreen().visibleFrame)
        window.setFrame(restingFrame, display: false); window.orderOut(nil)
    }
    private func saveRecord() {
        guard let placement else { return }
        let record = Record(edge: placement.edge, fraction: Double(placement.fraction), screenID: screenID, screenFrame: NSStringFromRect(lastScreenFrame), restingFrame: NSStringFromRect(restingFrame))
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: storageKey) }
    }
    private func persistRestingFrame() {
        let frame = (window.delegate as? WindowFrameKeeper)?.frameToPersist?(window) ?? restingFrame
        defaults.set(NSStringFromRect(frame), forKey: "frame.\(key)")
    }
}

private final class DockHandlePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor private final class DockHandleView: NSView {
    var onClick: () -> Void = {}
    var onDragStart: (NSPoint) -> Void = { _ in }
    var onDrag: (NSPoint) -> Void = { _ in }
    var onDragEnd: () -> Void = {}
    var onDragCancel: () -> Void = {}
    private var edge: DockEdge = .right
    private var preview = false
    private let material = NSVisualEffectView()
    private let glyph = DockHandleGlyph()
    private var trackingArea: NSTrackingArea?
    private var hovered = false
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 10; layer?.masksToBounds = true
        material.material = .hudWindow; material.blendingMode = .withinWindow; material.state = .active
        material.setAccessibilityElement(false); glyph.setAccessibilityElement(false)
        material.autoresizingMask = [.width, .height]; addSubview(material)
        addSubview(glyph)
        setAccessibilityElement(true); setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); material.frame = bounds; glyph.frame = bounds }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize); material.frame = bounds; glyph.frame = bounds
    }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    func configure(edge: DockEdge, preview: Bool, title: String) {
        self.edge = edge; self.preview = preview
        setAccessibilityLabel(preview ? "Release to dock at \(edge.label)" : "Show \(title), docked at \(edge.label)")
        setAccessibilityHelp("Click to bring the note back. Drag to move it out of the screen edge.")
        toolTip = preview ? "Release to tuck away" : title + " — click or drag to bring back"
        layer?.borderWidth = preview ? 1 : 0.5
        layer?.borderColor = NSColor(calibratedRed: 0.988, green: 0.431, blue: 0, alpha: preview ? 0.7 : 0.25).cgColor
        updateGlyph()
    }
    override func resetCursorRects() { super.resetCursorRects(); addCursorRect(bounds, cursor: .openHand) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); trackingArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; updateGlyph() }
    override func mouseExited(with event: NSEvent) { hovered = false; updateGlyph() }
    private func updateGlyph() { glyph.edge = edge; glyph.highlighted = hovered || preview; glyph.needsDisplay = true }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(); let show = NSMenuItem(title: "Bring Note Back", action: #selector(showNote), keyEquivalent: ""); show.target = self; menu.addItem(show)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func showNote() { onClick() }
    override func mouseDown(with event: NSEvent) {
        guard !preview, let window else { return }
        let start = window.convertPoint(toScreen: event.locationInWindow)
        var hasDragged = false
        NSCursor.closedHand.push(); defer { NSCursor.pop() }
        while true {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown], until: Date(timeIntervalSinceNow: 0.05), inMode: .eventTracking, dequeue: true) else {
                if NSEvent.pressedMouseButtons & 1 == 0 { if hasDragged { onDragEnd() }; return }
                continue
            }
            if next.type == .keyDown && next.keyCode == 53 { if hasDragged { onDragCancel() }; return }
            if next.type == .leftMouseUp { if hasDragged { onDragEnd() } else { onClick() }; return }
            if next.type == .leftMouseDragged {
                let point = (next.window ?? window).convertPoint(toScreen: next.locationInWindow)
                if !hasDragged, hypot(point.x - start.x, point.y - start.y) >= 5 { hasDragged = true; onDragStart(point) }
                if hasDragged { onDrag(point) }
            }
        }
    }
}

private final class DockHandleGlyph: NSView {
    var edge: DockEdge = .right
    var highlighted = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor(calibratedRed: 0.988, green: 0.431, blue: 0, alpha: highlighted ? 1 : 0.85)
        accent.setFill(); accent.setStroke()
        if edge.isCorner {
            let left = edge == .topLeft || edge == .bottomLeft
            let top = edge == .topLeft || edge == .topRight
            let x = bounds.midX + (left ? -5 : 5), y = bounds.midY + (top ? 5 : -5)
            let path = NSBezierPath(); path.lineWidth = 2.5; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.move(to: NSPoint(x: x, y: y + (top ? -10 : 10)))
            path.line(to: NSPoint(x: x, y: y))
            path.line(to: NSPoint(x: x + (left ? 10 : -10), y: y)); path.stroke()
        } else {
            let rect = edge.isVertical ? NSRect(x: bounds.midX - 1.5, y: bounds.midY - 14, width: 3, height: 28) : NSRect(x: bounds.midX - 14, y: bounds.midY - 1.5, width: 28, height: 3)
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
