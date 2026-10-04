import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main enum IdeaDockMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") { exit(SelfTests.run()) }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    var store: IdeaStore!
    var state: WorkspaceState!
    var preferences: Preferences!
    var attachments: AttachmentService!
    var quickDraft: CaptureDraft!
    var floatingDraft: CaptureDraft!
    var libraryWindow: NSWindow?
    var quickPanel: CapturePanel?
    var floatingPanel: CapturePanel?
    var settingsWindow: NSWindow?
    var palettePanel: CapturePanel?
    var noteWindows: [UUID: NSWindow] = [:]
    var frameKeepers: [String: WindowFrameKeeper] = [:]
    var edgeDockControllers: [String: EdgeDockController] = [:]
    var hotKeys: HotKeyService?
    var statusItem: NSStatusItem?
    var isCollapsed = false
    var previousApp: NSRunningApplication?
    var keyboardMonitor: Any?
    var preferenceObserver: NSObjectProtocol?
    var expandedFloatingFrame: NSRect?
    var uiTestMode = false
    var windowDefaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let arguments = CommandLine.arguments
            var root: URL?
            if let index = arguments.firstIndex(of: "--data-dir"), arguments.indices.contains(index + 1) { root = URL(fileURLWithPath: arguments[index + 1], isDirectory: true); uiTestMode = true }
            store = try IdeaStore(root: root)
            try store.removeOrphans()
            state = WorkspaceState(store: store)
            windowDefaults = uiTestMode ? UserDefaults(suiteName: "app.ideadock.UIVerification")! : .standard
            preferences = Preferences(defaults: windowDefaults)
            attachments = state.attachmentService
            quickDraft = CaptureDraft(store: store, service: attachments)
            floatingDraft = CaptureDraft(store: store, service: attachments)
            quickDraft.categoryID = preferences.defaultCategoryUUID
            floatingDraft.categoryID = preferences.defaultCategoryUUID
            if !uiTestMode {
                quickDraft.text = windowDefaults.string(forKey: "draft.quick") ?? ""
                floatingDraft.text = windowDefaults.string(forKey: "draft.floating") ?? ""
            }
            state.capture = { [weak self] in self?.showCapture() }
            state.captureDrop = { [weak self] providers in self?.showCaptureForDrop(providers) }
            state.detectTags = { [weak self] in self?.preferences.detectTags ?? true }
            state.openScope = { [weak self] scope in self?.showLibrary(scope: scope) }
            state.openIdea = { [weak self] id in self?.openIdea(id) }
            state.focusSearch = { [weak self] in self?.showLibrary(); self?.state.searchIdeas() }
            state.pasteClipboard = { [weak self] in self?.showCapture(clipboard: true) }
            state.settings = { [weak self] in self?.showSettings() }
            state.palette = { [weak self] in self?.showPalette() }
            state.toggleFloating = { [weak self] in self?.toggleFloating() }
            state.floatIdea = { [weak self] idea in self?.floatIdea(idea) }
            state.attachFiles = { [weak self] idea in self?.attachFiles(to: idea) }
            buildMenus()
            hotKeys = HotKeyService()
            applyPreferences()
            preferenceObserver = NotificationCenter.default.addObserver(forName: .ideaApplyPreferences, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.applyPreferences() } }
            installKeyboardNavigation()
            if preferences.openAtLaunch || uiTestMode { showLibrary() }
            if preferences.showFloatingAtLaunch { showFloating() }
            // Reopen individual notes only when their idea still exists.
            for value in windowDefaults.stringArray(forKey: "floating.ideaIDs") ?? [] {
                if let id = UUID(uuidString: value), let idea = store.ideas.first(where: { $0.id == id }) { floatIdea(idea, activate: false) }
            }
        } catch {
            let alert = NSAlert(); alert.messageText = "IdeaDock could not open its library"
            alert.informativeText = "Your existing data has been left in place.\n\n\(error.localizedDescription)"
            alert.runModal(); NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showLibrary(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store != nil else { return .terminateNow }
        if !store.save() {
            let alert = NSAlert(); alert.messageText = "Your latest changes could not be saved"; alert.informativeText = store.errorMessage ?? "Please try again before quitting."
            alert.addButton(withTitle: "Keep IdeaDock Open"); alert.addButton(withTitle: "Quit Anyway")
            return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        hotKeys?.unregisterAll()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
        if !uiTestMode {
            windowDefaults.set(quickDraft?.text ?? "", forKey: "draft.quick")
            windowDefaults.set(floatingDraft?.text ?? "", forKey: "draft.floating")
        }
        windowDefaults.set(noteWindows.keys.map(\.uuidString), forKey: "floating.ideaIDs")
        if let panel = floatingPanel { frameKeepers["floating"]?.saveFrame(panel, evenIfHidden: true) }
        for (id, window) in noteWindows { frameKeepers["note.\(id)"]?.saveFrame(window, evenIfHidden: true) }
        for controller in edgeDockControllers.values { controller.invalidate() }
        edgeDockControllers.removeAll()
        // Unsaved copied images are draft-owned and do not remain as orphaned files.
        if let quickDraft { attachments.discard(quickDraft.attachments) }
        if let floatingDraft { attachments.discard(floatingDraft.attachments) }
    }
    func showLibrary(scope: LibraryScope? = nil) {
        if let scope { state.navigate(scope) }
        if libraryWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "IdeaDock"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 620, height: 460)
            window.contentView = NSHostingView(rootView: LibraryView(state: state))
            keepFrame(window, key: "library"); libraryWindow = window
        }
        libraryWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func openIdea(_ id: UUID) {
        guard store.ideas.contains(where: { $0.id == id }) else { return }
        showLibrary()
        state.navigate(.recent)
        state.selectedID = id
        state.focusEditor(id)
    }
    func showCapture(clipboard: Bool = false) {
        if !clipboard, quickPanel?.isKeyWindow == true { hideCapture(); return }
        if quickPanel?.isVisible != true { previousApp = NSWorkspace.shared.frontmostApplication }
        if quickPanel == nil {
            let panel = makeCapturePanel(width: 540, height: 275)
            panel.title = "Quick Capture"; panel.minSize = NSSize(width: 420, height: 230)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: CaptureView(draft: quickDraft, preferences: preferences, onClose: { [weak self] in self?.hideCapture() }, onSaved: { [weak self] idea in
                guard let self else { return }; self.quickDraft.categoryID = self.preferences.defaultCategoryUUID; self.selectCaptured(idea)
                if self.preferences.closeAfterSave { self.hideCapture() }
            }))
            quickPanel = panel
        }
        if let panel = quickPanel {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            if let screen { let frame = screen.visibleFrame; panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + frame.height * 0.62 - panel.frame.height / 2)) }
            if quickDraft.categoryID == nil { quickDraft.categoryID = preferences.defaultCategoryUUID }
            if clipboard { quickDraft.pasteClipboard() }
            panel.makeKeyAndOrderFront(nil); panel.orderFrontRegardless(); quickDraft.focusToken += 1
        }
    }
    func showCaptureForDrop(_ providers: [NSItemProvider]) {
        if quickPanel?.isVisible != true { showCapture() }
        quickDraft.drop(providers)
    }
    func hideCapture() {
        quickPanel?.orderOut(nil)
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp.activate(options: []) }
        previousApp = nil
    }
    func selectCaptured(_ idea: Idea) { state.scope = .recent; state.search = ""; state.filter = nil; state.dateFilter = .anyTime; state.selectedID = idea.id }
    func showFloating() {
        if floatingPanel == nil {
            let panel = makeCapturePanel(width: 350, height: 300)
            panel.title = "IdeaDock Capture"; panel.minSize = NSSize(width: 300, height: 250)
            panel.contentView = NSHostingView(rootView: floatingView())
            keepFrame(panel, key: "floating")
            floatingPanel = panel
            if windowDefaults.bool(forKey: "floating.collapsed") { setCollapsed(true) }
            let controller = installEdgeDockController(panel, key: "floating", title: { "IdeaDock Capture" })
            frameKeepers["floating"]?.frameToPersist = { [weak self, weak controller] window in
                let base = controller?.frameForPersistence ?? window.frame
                guard let self, self.isCollapsed, let expanded = self.expandedFloatingFrame else { return base }
                let size = NSSize(width: max(300, expanded.width), height: max(250, expanded.height))
                let frame = NSRect(x: base.minX, y: base.maxY - size.height, width: size.width, height: size.height)
                guard let screen = window.screen ?? NSScreen.screens.first(where: { $0.visibleFrame.intersects(base) }) ?? NSScreen.main else { return frame }
                return EdgeDockGeometry.restoredFrame(frame, in: screen.visibleFrame)
            }
        }
        applyPanelPreferences()
        edgeDockControllers["floating"]?.show()
        if let panel = floatingPanel { frameKeepers["floating"]?.saveFrame(panel, evenIfHidden: true) }
    }
    func floatingView() -> CaptureView {
        CaptureView(draft: floatingDraft, preferences: preferences, quick: false, collapsed: isCollapsed,
                    onClose: { [weak self] in self?.hideFloating() },
                    onExpand: { [weak self] in self?.setCollapsed(false) },
                    onCollapse: { [weak self] in self?.setCollapsed(true) },
                    onLibrary: { [weak self] in self?.showLibrary() },
                    onOpen: { [weak self] id in self?.openIdea(id) },
                    onSaved: { [weak self] idea in self?.floatingDraft.categoryID = self?.preferences.defaultCategoryUUID; self?.selectCaptured(idea) })
    }
    func setCollapsed(_ collapsed: Bool) {
        guard let panel = floatingPanel, isCollapsed != collapsed else { return }
        let old = panel.frame; isCollapsed = collapsed
        windowDefaults.set(collapsed, forKey: "floating.collapsed")
        panel.contentView = NSHostingView(rootView: floatingView())
        if collapsed {
            expandedFloatingFrame = old
            panel.minSize = NSSize(width: 260, height: 52); panel.maxSize = NSSize(width: 600, height: 52)
            panel.setFrame(NSRect(x: old.minX, y: old.maxY - 52, width: max(260, old.width), height: 52), display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        } else {
            panel.minSize = NSSize(width: 300, height: 250); panel.maxSize = NSSize(width: 1000, height: 1000)
            let savedSize = expandedFloatingFrame?.size ?? NSSize(width: 350, height: 300)
            let size = NSSize(width: max(panel.minSize.width, savedSize.width), height: max(panel.minSize.height, savedSize.height))
            var frame = NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height)
            if let screen = panel.screen ?? NSScreen.screens.first(where: { $0.visibleFrame.intersects(old) }) ?? NSScreen.main {
                frame = EdgeDockGeometry.restoredFrame(frame, in: screen.visibleFrame)
            }
            expandedFloatingFrame = frame
            panel.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            panel.makeKeyAndOrderFront(nil); floatingDraft.focusToken += 1
        }
    }
    func hideFloating() {
        if let controller = edgeDockControllers["floating"] { controller.hide() }
        else { floatingPanel?.orderOut(nil) }
        if let panel = floatingPanel { frameKeepers["floating"]?.saveFrame(panel, evenIfHidden: true) }
    }
    func toggleFloating() {
        if edgeDockControllers["floating"]?.isVisible ?? floatingPanel?.isVisible ?? false { hideFloating() }
        else { showFloating() }
    }
    func applyPanelPreferences() {
        for panel in [floatingPanel].compactMap({ $0 }) {
            panel.level = preferences.alwaysOnTop ? .floating : .normal
            panel.collectionBehavior = preferences.allSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.alphaValue = preferences.opacity
        }
        for window in noteWindows.values {
            window.level = preferences.alwaysOnTop ? .floating : .normal
            window.collectionBehavior = preferences.allSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace]
            window.alphaValue = preferences.opacity
        }
        for controller in edgeDockControllers.values { controller.synchronizePreferences() }
    }
    func keepFrame(_ window: NSWindow, key: String, onClose: @escaping () -> Void = {}) {
        let keeper = WindowFrameKeeper(key: key, defaults: windowDefaults); keeper.onClose = onClose
        frameKeepers[key] = keeper; window.delegate = keeper; keeper.restore(window)
    }
    @discardableResult func installEdgeDockController(_ window: NSWindow, key: String, title: @escaping () -> String) -> EdgeDockController {
        let controller = EdgeDockController(window: window, key: key, defaults: windowDefaults, title: title)
        edgeDockControllers[key] = controller
        let previousProvider = frameKeepers[key]?.frameToPersist
        frameKeepers[key]?.frameToPersist = { [weak controller] window in
            controller?.frameForPersistence ?? previousProvider?(window) ?? window.frame
        }
        return controller
    }
    func applyPreferences() {
        NSApp.setActivationPolicy(preferences.showDock ? .regular : .accessory)
        switch preferences.appearance { case "dark": NSApp.appearance = NSAppearance(named: .darkAqua); case "light": NSApp.appearance = NSAppearance(named: .aqua); default: NSApp.appearance = nil }
        applyPanelPreferences()
        if !quickDraft.canSave { quickDraft.categoryID = preferences.defaultCategoryUUID }
        if !floatingDraft.canSave { floatingDraft.categoryID = preferences.defaultCategoryUUID }
        if preferences.showMenuBar { createStatusItem() }
        else if let statusItem { NSStatusBar.system.removeStatusItem(statusItem); self.statusItem = nil }
        preferences.shortcutError = nil
        if preferences.isRecordingShortcut { hotKeys?.unregisterAll(); return }
        var shortcutErrors: [String] = []
        do { try hotKeys?.register(id: 1, keyCode: UInt32(preferences.captureKeyCode), modifiers: UInt32(preferences.captureModifiers)) { [weak self] in self?.showCapture() } }
        catch { shortcutErrors.append("Quick capture: " + error.localizedDescription) }
        do { try hotKeys?.register(id: 2, keyCode: UInt32(preferences.clipboardKeyCode), modifiers: UInt32(preferences.clipboardModifiers)) { [weak self] in self?.showCapture(clipboard: true) } }
        catch { shortcutErrors.append("Clipboard capture: " + error.localizedDescription) }
        if !shortcutErrors.isEmpty { preferences.shortcutError = shortcutErrors.joined(separator: "\n") }

    }
    func attachFiles(to idea: Idea) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                guard let self, self.store.ideas.contains(where: { $0.id == idea.id }) else { return }
                for url in panel.urls { do { idea.attachments.append(try self.attachments.fromFile(url)) } catch { self.store.errorMessage = error.localizedDescription } }
                self.store.changed(idea)
            }
        }
    }
    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 710, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "IdeaDock Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(store: store, preferences: preferences, onApply: { [weak self] in self?.applyPreferences() }, onExportJSON: { [weak self] in self?.exportJSON() }, onExportMarkdown: { [weak self] in self?.exportMarkdown() }, onImport: { [weak self] in self?.importJSON() }, onDeleteAll: { [weak self] in self?.deleteAll() }))
            window.center(); settingsWindow = window
        }
        preferences.refreshLoginItemStatus(); settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func exportJSON() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "IdeaDock-backup.json"; panel.allowedContentTypes = [.json]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in guard let self else { return }; do { try ExportService.exportJSON(store: self.store, to: url) } catch { self.presentError(error) } }
        }
    }
    func exportMarkdown() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.prompt = "Export Here"; panel.message = "Choose a folder for your Markdown export."
        panel.begin { [weak self] response in
            guard response == .OK, let parent = panel.url else { return }
            Task { @MainActor in guard let self else { return }; do { let folder = parent.appendingPathComponent("IdeaDock Export \(Int(Date.now.timeIntervalSince1970))", isDirectory: true); try ExportService.exportMarkdown(store: self.store, to: folder); NSWorkspace.shared.activateFileViewerSelecting([folder]) } catch { self.presentError(error) } }
        }
    }
    func importJSON() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                do { let count = try ExportService.importJSON(store: self.store, from: url); let alert = NSAlert(); alert.messageText = "\(count) ideas imported"; alert.informativeText = "Existing ideas were preserved."; alert.runModal() }
                catch { self.presentError(error) }
            }
        }
    }
    func deleteAll() {
        // Settings performs the explicit destructive confirmation before this callback.
        state.selectedID = nil
        for window in Array(noteWindows.values) { window.close() }
        for key in edgeDockControllers.keys.filter({ $0.hasPrefix("note.") }) { edgeDockControllers.removeValue(forKey: key)?.invalidate() }
        for key in frameKeepers.keys.filter({ $0.hasPrefix("note.") }) { frameKeepers.removeValue(forKey: key) }
        noteWindows = [:]
        for idea in Array(store.ideas) { store.delete(idea) }
        quickDraft.clear(); floatingDraft.clear()
    }
    func presentError(_ error: Error) { let alert = NSAlert(); alert.messageText = "That didn’t work"; alert.informativeText = error.localizedDescription; alert.runModal() }
    func floatIdea(_ idea: Idea, activate: Bool = true) {
        let id = idea.id
        let key = "note.\(id)"
        if let window = noteWindows[id] {
            if let controller = edgeDockControllers[key] { controller.reveal() }
            else { window.makeKeyAndOrderFront(nil) }
            frameKeepers[key]?.saveFrame(window, evenIfHidden: true)
            if activate { NSApp.activate(ignoringOtherApps: true) }
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 370, height: 380), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = idea.title; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden; window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 300, height: 230)
        window.contentView = NSHostingView(rootView: FloatingIdeaView(state: state, preferences: preferences, ideaID: id))
        keepFrame(window, key: key) { [weak self, weak window] in
            if let window { self?.frameKeepers[key]?.saveFrame(window, evenIfHidden: true) }
            self?.edgeDockControllers.removeValue(forKey: key)?.invalidate()
            self?.noteWindows.removeValue(forKey: id)
            self?.frameKeepers.removeValue(forKey: key)
        }
        let controller = installEdgeDockController(window, key: key, title: { [weak self] in
            self?.store.ideas.first(where: { $0.id == id })?.title ?? "IdeaDock"
        })
        noteWindows[id] = window; applyPanelPreferences()
        if activate { controller.reveal(); NSApp.activate(ignoringOtherApps: true) }
        else { controller.show() }
        frameKeepers[key]?.saveFrame(window, evenIfHidden: true)
    }
    func showPalette() {
        if palettePanel?.isVisible == true { palettePanel?.orderOut(nil); return }
        let panel = makeCapturePanel(width: 520, height: 400); panel.title = "Command Palette"; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CommandPaletteView(state: state, contextIdea: activeIdea, close: { [weak panel] in panel?.orderOut(nil) }))
        panel.center(); palettePanel = panel; panel.makeKeyAndOrderFront(nil)
    }
    func buildMenus() {
        let main = NSMenu()
        let application = NSMenuItem(); main.addItem(application)
        let appMenu = NSMenu(); application.submenu = appMenu
        menuItem("About IdeaDock", action: #selector(about), into: appMenu)
        menuItem("Settings…", action: #selector(settingsAction), key: ",", into: appMenu)
        appMenu.addItem(.separator())
        menuItem("Hide IdeaDock", action: #selector(NSApplication.hide(_:)), key: "h", target: NSApp, into: appMenu)
        menuItem("Quit IdeaDock", action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp, into: appMenu)
        let file = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); let fileMenu = NSMenu(title: "File"); file.submenu = fileMenu; main.addItem(file)
        menuItem("New Idea", action: #selector(captureAction), key: "n", into: fileMenu)
        menuItem("Paste Clipboard", action: #selector(clipboardAction), key: "v", modifiers: [.command, .shift], into: fileMenu)
        menuItem("Save", action: #selector(saveAction), key: "s", into: fileMenu)
        menuItem("Finish Capture", action: #selector(finishCaptureAction), key: "\r", into: fileMenu)
        fileMenu.addItem(.separator())
        menuItem("Open Library", action: #selector(libraryAction), key: "o", into: fileMenu)
        menuItem("Close Window", action: #selector(NSWindow.performClose(_:)), key: "w", target: nil, into: fileMenu)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); let editMenu = NSMenu(title: "Edit"); edit.submenu = editMenu; main.addItem(edit)
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] { menuItem(title, action: action, key: key, target: nil, into: editMenu) }
        menuItem("Redo", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift], target: nil, into: editMenu)
        editMenu.addItem(.separator())
        menuItem("Search Ideas", action: #selector(searchAction), key: "f", into: editMenu)
        menuItem("Command Palette", action: #selector(paletteAction), key: "k", into: editMenu)
        menuItem("Pin / Unpin Idea", action: #selector(pinAction), key: "p", modifiers: [.command, .shift], into: editMenu)
        menuItem("Archive / Delete Idea", action: #selector(archiveAction), key: "\u{8}", into: editMenu)
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: ""); let windowMenu = NSMenu(title: "Window"); windowItem.submenu = windowMenu; main.addItem(windowItem)
        menuItem("Toggle Floating Capture", action: #selector(floatingAction), into: windowMenu)
        let dockItem = NSMenuItem(title: "Dock Current Note", action: nil, keyEquivalent: "")
        let dockMenu = NSMenu(title: "Dock Current Note")
        for edge in DockEdge.allCases {
            let item = menuItem(edge.label, action: #selector(dockCurrentNote(_:)), target: self, into: dockMenu)
            item.representedObject = edge.rawValue
        }
        dockItem.submenu = dockMenu; windowMenu.addItem(dockItem)
        menuItem("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m", target: nil, into: windowMenu)
        windowMenu.delegate = self
        NSApp.mainMenu = main; NSApp.windowsMenu = windowMenu
    }
    @discardableResult func menuItem(_ title: String, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil, into menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.keyEquivalentModifierMask = modifiers
        // Responder-chain actions have nil targets; app actions target this delegate.
        item.target = target ?? (NSStringFromSelector(action).hasSuffix(":") ? nil : self)
        menu.addItem(item); return item
    }
    func createStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "IdeaDock")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menuItem("Quick Capture", action: #selector(captureAction), into: menu)
        menuItem("Open IdeaDock", action: #selector(libraryAction), into: menu)
        menuItem("Inbox", action: #selector(inboxAction), into: menu)
        menuItem("Pinned", action: #selector(pinnedAction), into: menu)
        menu.addItem(.separator())
        menuItem("Paste Clipboard", action: #selector(clipboardAction), into: menu)
        menuItem("Toggle Floating Window", action: #selector(floatingAction), into: menu)
        menu.addItem(.separator())
        menuItem("Settings…", action: #selector(settingsAction), into: menu)
        menuItem("Quit IdeaDock", action: #selector(NSApplication.terminate(_:)), target: NSApp, into: menu)
        item.menu = menu; statusItem = item
    }
    func installKeyboardNavigation() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            var result: NSEvent? = event
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.keyCode == 53 {
                    if self.quickPanel?.isKeyWindow == true { self.hideCapture(); result = nil; return }
                    if self.palettePanel?.isKeyWindow == true { self.palettePanel?.orderOut(nil); result = nil; return }
                }
            }
            return result
        }
    }
    @objc func captureAction() { showCapture() }
    @objc func clipboardAction() { showCapture(clipboard: true) }
    @objc func libraryAction() { showLibrary() }
    @objc func inboxAction() { showLibrary(scope: .inbox) }
    @objc func pinnedAction() { showLibrary(scope: .pinned) }
    @objc func settingsAction() { showSettings() }
    @objc func floatingAction() { toggleFloating() }
    @objc func paletteAction() { showPalette() }
    @objc func searchAction() { showLibrary(); state.searchIdeas() }
    var activeIdea: Idea? {
        if libraryWindow?.isKeyWindow == true { return state.selected }
        if let entry = noteWindows.first(where: { $0.value.isKeyWindow }) { return store.ideas.first { $0.id == entry.key } }
        return nil
    }
    private var activeDockController: EdgeDockController? {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow, window.isVisible, !window.isMiniaturized else { return nil }
        return edgeDockControllers.first { entry in
            (entry.key == "floating" || entry.key.hasPrefix("note.")) && entry.value.window === window
        }?.value
    }
    func menuWillOpen(_ menu: NSMenu) {
        if menu === NSApp.windowsMenu { menu.item(withTitle: "Dock Current Note")?.isEnabled = activeDockController != nil }
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(pinAction) || item.action == #selector(archiveAction) { return activeIdea != nil }
        if item.action == #selector(dockCurrentNote(_:)) { return activeDockController != nil }
        return true
    }
    @objc func dockCurrentNote(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let edge = DockEdge(rawValue: value), let controller = activeDockController else { return }
        controller.dockAtEdge(edge)
    }
    @objc func pinAction() { guard let idea = activeIdea else { return }; idea.isPinned.toggle(); store.changed(idea) }
    @objc func archiveAction() {
        guard let idea = activeIdea else { return }
        if libraryWindow?.isKeyWindow == true { state.archiveSelected() }
        else { let id = idea.id; store.archive(idea); noteWindows[id]?.close() }
    }
    @objc func saveAction() {
        if quickPanel?.isKeyWindow == true || floatingPanel?.isKeyWindow == true { finishCaptureAction(); return }
        saveStore()
    }
    func saveStore() { if !store.save() { let alert = NSAlert(); alert.messageText = "Could not save changes"; alert.informativeText = store.errorMessage ?? ""; alert.runModal() } }
    @objc func finishCaptureAction() {
        if quickPanel?.isKeyWindow == true { if let idea = quickDraft.save(detectTags: preferences.detectTags) { quickDraft.categoryID = preferences.defaultCategoryUUID; selectCaptured(idea); if preferences.closeAfterSave { hideCapture() } } }
        else if floatingPanel?.isKeyWindow == true { if let idea = floatingDraft.save(detectTags: preferences.detectTags) { floatingDraft.categoryID = preferences.defaultCategoryUUID; selectCaptured(idea) } }
        else { saveStore() }
    }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "IdeaDock", .applicationVersion: "1.0.0", .credits: NSAttributedString(string: "Capture first. Organize later.\nBuilt for the ideas that arrive while you work.")]) }
}
