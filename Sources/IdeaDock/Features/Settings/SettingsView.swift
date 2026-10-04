import AppKit
import Carbon
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General", capture = "Capture", appearance = "Appearance", data = "Data", about = "About"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .capture: "square.and.pencil"
        case .appearance: "paintbrush"
        case .data: "externaldrive"
        case .about: "info.circle"
        }
    }
    var subtitle: String {
        switch self {
        case .general: "Make IdeaDock fit your day."
        case .capture: "A thought should never have to wait."
        case .appearance: "A comfortable place for your ideas."
        case .data: "Your library stays on this Mac."
        case .about: "A small home for your next big idea."
        }
    }
}

struct SettingsView: View {
    let store: IdeaStore
    @Bindable var preferences: Preferences
    let onApply: () -> Void
    let onExportJSON: () -> Void
    let onExportMarkdown: () -> Void
    let onImport: () -> Void
    let onDeleteAll: () -> Void
    @ViewState private var pane: SettingsPane? = .general
    @ViewState private var confirmingDelete = false
    @ViewState private var recorderError: String?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(SettingsPane.allCases, selection: $pane) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .padding(.vertical, 5)
                        .tag(item)
                }
                .listStyle(.sidebar)
                .padding(.top, 12)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.orange)
                    Text("IdeaDock").fontWeight(.medium)
                    Spacer()
                    Text(version).foregroundStyle(.secondary).font(.caption)
                }
                .font(.callout)
                .padding(18)
            }
            .navigationSplitViewColumnWidth(min: 166, ideal: 180, max: 200)
        } detail: {
            let selected = pane ?? .general
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selected.rawValue).font(.system(size: 24, weight: .semibold))
                    Text(selected.subtitle).font(.callout).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 10)
                Form {
                    switch selected {
                    case .general: general
                    case .capture: capture
                    case .appearance: appearance
                    case .data: data
                    case .about: about
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.orange)
        .frame(minWidth: 700, idealWidth: 760, minHeight: 550, idealHeight: 610)
        .preferredColorScheme(preferences.preferredColorScheme)
        .onAppear { validateDefaultCategory() }
        .onChange(of: store.categories.map(\.id)) { _, _ in validateDefaultCategory() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            preferences.refreshLoginItemStatus()
        }
        .alert("Delete every idea?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All Ideas", role: .destructive) { onDeleteAll() }
        } message: {
            Text("This permanently deletes all \(store.ideas.count) ideas and their saved attachments from this Mac. Export a backup first if you want to keep a copy.")
        }
    }

    private var general: some View {
        Group {
            Section("Launch") {
                Toggle("Launch at login", isOn: Binding(
                    get: { preferences.launchAtLogin || preferences.loginItemRequiresApproval },
                    set: { preferences.setLaunchAtLogin($0); onApply() }
                ))
                if preferences.loginItemRequiresApproval {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Approval is needed in System Settings before IdeaDock can launch at login.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open Login Items Settings…") { preferences.openLoginItemSettings() }
                    }
                }
                if let error = preferences.loginItemError { inlineError(error) }
                Toggle("Open library on launch", isOn: applied(\.openAtLaunch))
                Toggle("Show floating capture on launch", isOn: applied(\.showFloatingAtLaunch))
            }
            Section {
                Toggle("Show in the Dock", isOn: applied(\.showDock))
                Toggle("Show in the menu bar", isOn: applied(\.showMenuBar))
                    .disabled(!preferences.showDock)
            } header: {
                Text("Access")
            } footer: {
                Text("Keep at least one visible so IdeaDock is always easy to reopen.")
            }
        }
    }

    private var capture: some View {
        Group {
            Section {
                shortcutRow("Quick capture", detail: "Open the capture panel from any app.", keyCode: preferences.captureKeyCode, modifiers: preferences.captureModifiers) { code, modifiers in
                    guard code != preferences.clipboardKeyCode || modifiers != preferences.clipboardModifiers else {
                        recorderError = "Quick capture and clipboard capture need different shortcuts."
                        return
                    }
                    preferences.captureKeyCode = code
                    preferences.captureModifiers = modifiers
                    recorderError = nil
                    onApply()
                }
                shortcutRow("Capture clipboard", detail: "Save your clipboard when you press the shortcut.", keyCode: preferences.clipboardKeyCode, modifiers: preferences.clipboardModifiers) { code, modifiers in
                    guard code != preferences.captureKeyCode || modifiers != preferences.captureModifiers else {
                        recorderError = "Quick capture and clipboard capture need different shortcuts."
                        return
                    }
                    preferences.clipboardKeyCode = code
                    preferences.clipboardModifiers = modifiers
                    recorderError = nil
                    onApply()
                }
                if let error = recorderError ?? preferences.shortcutError { inlineError(error) }
            } header: {
                Text("Global shortcuts")
            } footer: {
                Text("Click a shortcut and press a new combination with ⌘, ⌥, or ⌃. Escape cancels. The clipboard is read only when you ask to capture it.")
            }
            Section("Saving") {
                Picker("Default category", selection: applied(\.defaultCategoryID)) {
                    Text("Inbox").tag("")
                    ForEach(store.categories.filter { !$0.isInbox }) { category in
                        Label(category.name, systemImage: category.icon).tag(category.id.uuidString)
                    }
                }
                Toggle("Close quick capture after saving", isOn: applied(\.closeAfterSave))
                Toggle("Recognize #tags automatically", isOn: applied(\.detectTags))
            }
            Section {
                Button("Restore Default Shortcuts") {
                    preferences.captureKeyCode = 49
                    preferences.captureModifiers = Int(optionKey)
                    preferences.clipboardKeyCode = 9
                    preferences.clipboardModifiers = Int(cmdKey | shiftKey)
                    recorderError = nil
                    onApply()
                }
            }
        }
    }

    private var appearance: some View {
        Group {
            Section("Theme") {
                Picker("Appearance", selection: applied(\.appearance)) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            Section("Floating windows") {
                Toggle("Keep on top of other windows", isOn: applied(\.alwaysOnTop))
                Toggle("Show on all Spaces", isOn: applied(\.allSpaces))
                Toggle("Use a translucent background", isOn: applied(\.translucent))
                LabeledContent("Window opacity") {
                    HStack(spacing: 12) {
                        Slider(value: applied(\.opacity), in: 0.5...1, step: 0.01)
                            .frame(maxWidth: 190)
                            .accessibilityLabel("Floating window opacity")
                        Text("\(Int((preferences.opacity * 100).rounded()))%")
                            .monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var data: some View {
        Group {
            Section {
                LabeledContent("Ideas", value: "\(store.ideas.count)")
                LabeledContent("Categories", value: "\(store.categories.count)")
                LabeledContent("Library folder") {
                    Button("Show in Finder…") { NSWorkspace.shared.open(store.root) }
                }
                Text(store.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            } header: {
                Text("Local storage")
            } footer: {
                Text("Ideas, categories, and attachments are saved locally. There is no account or cloud service.")
            }
            Section {
                LabeledContent("Backup and restore") {
                    HStack {
                        Button("Export JSON…", action: onExportJSON)
                        Button("Import JSON…", action: onImport)
                    }
                }
                LabeledContent("Readable copy") {
                    Button("Export Markdown…", action: onExportMarkdown)
                }
            } header: {
                Text("Import & export")
            } footer: {
                Text("JSON includes your library and saved images. Markdown creates readable notes with an attachments folder.")
            }
            Section {
                LabeledContent("Delete library contents") {
                    Button("Delete All Ideas…", role: .destructive) { confirmingDelete = true }
                        .disabled(store.ideas.isEmpty)
                }
            } footer: {
                Text("Deleting ideas is permanent. Your categories and preferences stay in place.")
            }
        }
    }

    private var about: some View {
        Group {
            Section {
                HStack(alignment: .center, spacing: 18) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 42, weight: .light)).foregroundStyle(.orange)
                        .frame(width: 64, height: 72)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("IdeaDock").font(.title2.weight(.semibold))
                        Text("Version \(version)").font(.callout).foregroundStyle(.secondary)
                        Text("Capture first. Organize when you're ready.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
            }
            Section("Built for your Mac") {
                Label("SwiftUI interface and a local SwiftData library", systemImage: "macwindow")
                Label("No account, analytics, or clipboard monitoring", systemImage: "lock.shield")
                Label("Works offline", systemImage: "wifi.slash")
            }
        }
    }

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }

    private func validateDefaultCategory() {
        guard !preferences.defaultCategoryID.isEmpty else { return }
        if let category = store.categories.first(where: { $0.id == preferences.defaultCategoryUUID }), !category.isInbox { return }
        preferences.defaultCategoryID = ""
        onApply()
    }

    private func applied<Value>(_ path: ReferenceWritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(get: { preferences[keyPath: path] }, set: { preferences[keyPath: path] = $0; onApply() })
    }

    private func inlineError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func shortcutRow(_ title: String, detail: String, keyCode: Int, modifiers: Int, onRecord: @escaping (Int, Int) -> Void) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ShortcutRecorder(keyCode: keyCode, modifiers: modifiers, onRecord: onRecord, onError: { recorderError = $0 }, onRecordingChanged: { isRecording in
                preferences.isRecordingShortcut = isRecording
                onApply()
            })
                .frame(width: 140, height: 28)
                .accessibilityLabel("\(title) shortcut")
                .accessibilityValue(ShortcutDisplay.label(keyCode: keyCode, modifiers: modifiers))
        }
        .padding(.vertical, 3)
    }
}

/// A native button with a local event monitor only while the user is recording.
private struct ShortcutRecorder: NSViewRepresentable {
    let keyCode: Int
    let modifiers: Int
    let onRecord: (Int, Int) -> Void
    let onError: (String?) -> Void
    let onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        updateNSView(button, context: context)
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.shortcutLabel = ShortcutDisplay.label(keyCode: keyCode, modifiers: modifiers)
        button.onRecord = onRecord
        button.onError = onError
        button.onRecordingChanged = onRecordingChanged
        button.refreshTitle()
    }
    static func dismantleNSView(_ button: RecorderButton, coordinator: ()) { button.stopRecording() }
}

private final class RecorderButton: NSButton {
    var shortcutLabel = ""
    var onRecord: ((Int, Int) -> Void)?
    var onError: ((String?) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var isRecording = false

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        controlSize = .regular
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        target = self
        action = #selector(beginRecording)
        toolTip = "Click, then press a new keyboard shortcut. Escape cancels."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func beginRecording() {
        guard !isRecording, let window else { stopRecording(); return }
        window.makeFirstResponder(self)
        isRecording = true
        onRecordingChanged?(true)
        onError?(nil)
        refreshTitle()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window, window.isKeyWindow, event.window === window, self.isRecording else { return event }
            if event.keyCode == 53 { self.stopRecording(); return nil }
            let modifiers = ShortcutDisplay.carbonModifiers(event.modifierFlags)
            guard ShortcutDisplay.validModifiers(modifiers) != nil else {
                self.onError?("Include Command, Option, or Control in your shortcut.")
                NSSound.beep()
                return nil
            }
            self.stopRecording()
            self.onRecord?(Int(event.keyCode), modifiers)
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.stopRecording()
        }
    }

    func refreshTitle() {
        title = isRecording ? "Press shortcut…" : shortcutLabel
        setAccessibilityValue(isRecording ? "Recording shortcut" : shortcutLabel)
    }

    func stopRecording() {
        let wasRecording = isRecording
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        isRecording = false
        refreshTitle()
        if wasRecording { onRecordingChanged?(false) }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
}
