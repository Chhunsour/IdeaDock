import AppKit
import Carbon
import Observation
import ServiceManagement
import SwiftUI

/// Small preferences live in UserDefaults; the library itself lives in SwiftData.
@MainActor @Observable final class Preferences {
    @ObservationIgnored private let defaults: UserDefaults
    private static let prefix = "IdeaDock."

    var showDock: Bool { didSet { persist("showDock", showDock); keepAnEntryPoint() } }
    var showMenuBar: Bool { didSet { persist("showMenuBar", showMenuBar); keepAnEntryPoint() } }
    var alwaysOnTop: Bool { didSet { persist("alwaysOnTop", alwaysOnTop) } }
    var allSpaces: Bool { didSet { persist("allSpaces", allSpaces) } }
    var translucent: Bool { didSet { persist("translucent", translucent) } }
    var openAtLaunch: Bool { didSet { persist("openAtLaunch", openAtLaunch) } }
    var showFloatingAtLaunch: Bool { didSet { persist("showFloatingAtLaunch", showFloatingAtLaunch) } }
    var closeAfterSave: Bool { didSet { persist("closeAfterSave", closeAfterSave) } }
    var detectTags: Bool { didSet { persist("detectTags", detectTags) } }
    var appearance: String {
        didSet {
            if !["system", "light", "dark"].contains(appearance) { appearance = "system" }
            persist("appearance", appearance)
        }
    }
    var opacity: Double {
        didSet {
            let clamped = opacity.isFinite ? min(max(opacity, 0.5), 1) : 0.97
            if opacity != clamped { opacity = clamped }
            persist("opacity", clamped)
        }
    }
    var defaultCategoryID: String { didSet { persist("defaultCategoryID", defaultCategoryID) } }
    var captureKeyCode: Int { didSet { persist("captureKeyCode", captureKeyCode) } }
    var captureModifiers: Int { didSet { persist("captureModifiers", captureModifiers) } }
    var clipboardKeyCode: Int { didSet { persist("clipboardKeyCode", clipboardKeyCode) } }
    var clipboardModifiers: Int { didSet { persist("clipboardModifiers", clipboardModifiers) } }

    /// Set by the window owner if the operating system rejects a shortcut.
    var shortcutError: String?
    /// Temporarily suspends global registrations while a Settings recorder has focus.
    var isRecordingShortcut = false
    private(set) var launchAtLogin = false
    private(set) var loginItemRequiresApproval = false
    private(set) var loginItemError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let values: [String: Any] = [
            "showDock": true, "showMenuBar": true, "alwaysOnTop": true,
            "allSpaces": true, "translucent": true, "openAtLaunch": true,
            "showFloatingAtLaunch": true, "closeAfterSave": true, "detectTags": true,
            "appearance": "system", "opacity": 0.97, "defaultCategoryID": "",
            "captureKeyCode": 49, "captureModifiers": Int(optionKey),
            "clipboardKeyCode": 9, "clipboardModifiers": Int(cmdKey | shiftKey)
        ]
        defaults.register(defaults: Dictionary(uniqueKeysWithValues: values.map { (Self.prefix + $0.key, $0.value) }))
        func bool(_ key: String) -> Bool { defaults.bool(forKey: Self.prefix + key) }
        func int(_ key: String) -> Int { defaults.integer(forKey: Self.prefix + key) }
        showDock = bool("showDock")
        showMenuBar = bool("showMenuBar")
        alwaysOnTop = bool("alwaysOnTop")
        allSpaces = bool("allSpaces")
        translucent = bool("translucent")
        openAtLaunch = bool("openAtLaunch")
        showFloatingAtLaunch = bool("showFloatingAtLaunch")
        closeAfterSave = bool("closeAfterSave")
        detectTags = bool("detectTags")
        let storedAppearance = defaults.string(forKey: Self.prefix + "appearance") ?? "system"
        appearance = ["system", "light", "dark"].contains(storedAppearance) ? storedAppearance : "system"
        let storedOpacity = defaults.double(forKey: Self.prefix + "opacity")
        opacity = storedOpacity.isFinite ? min(max(storedOpacity, 0.5), 1) : 0.97
        defaultCategoryID = defaults.string(forKey: Self.prefix + "defaultCategoryID") ?? ""
        captureKeyCode = (0...127).contains(int("captureKeyCode")) ? int("captureKeyCode") : 49
        captureModifiers = ShortcutDisplay.validModifiers(int("captureModifiers")) ?? Int(optionKey)
        clipboardKeyCode = (0...127).contains(int("clipboardKeyCode")) ? int("clipboardKeyCode") : 9
        clipboardModifiers = ShortcutDisplay.validModifiers(int("clipboardModifiers")) ?? Int(cmdKey | shiftKey)
        keepAnEntryPoint()
        refreshLoginItemStatus()
    }

    var defaultCategoryUUID: UUID? { UUID(uuidString: defaultCategoryID) }
    var captureShortcutLabel: String { ShortcutDisplay.label(keyCode: captureKeyCode, modifiers: captureModifiers) }
    var clipboardShortcutLabel: String { ShortcutDisplay.label(keyCode: clipboardKeyCode, modifiers: clipboardModifiers) }
    var preferredColorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }

    func refreshLoginItemStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        loginItemRequiresApproval = status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .notRegistered || service.status == .notFound { try service.register() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            loginItemError = "Launch at login could not be \(enabled ? "enabled" : "disabled"): \(error.localizedDescription)"
        }
        refreshLoginItemStatus()
    }

    func openLoginItemSettings() { SMAppService.openSystemSettingsLoginItems() }

    private func persist(_ key: String, _ value: Any) { defaults.set(value, forKey: Self.prefix + key) }
    private func keepAnEntryPoint() {
        if !showDock && !showMenuBar { showMenuBar = true }
    }
}

enum ShortcutDisplay {
    static func validModifiers(_ value: Int) -> Int? {
        let cleaned = value & Int(cmdKey | shiftKey | optionKey | controlKey)
        return cleaned & Int(cmdKey | optionKey | controlKey) != 0 ? cleaned : nil
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var modifiers = 0
        if flags.contains(.control) { modifiers |= Int(controlKey) }
        if flags.contains(.option) { modifiers |= Int(optionKey) }
        if flags.contains(.shift) { modifiers |= Int(shiftKey) }
        if flags.contains(.command) { modifiers |= Int(cmdKey) }
        return modifiers
    }

    static func label(keyCode: Int, modifiers: Int) -> String {
        var symbols = ""
        if modifiers & Int(controlKey) != 0 { symbols += "⌃" }
        if modifiers & Int(optionKey) != 0 { symbols += "⌥" }
        if modifiers & Int(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & Int(cmdKey) != 0 { symbols += "⌘" }
        return symbols + keyName(keyCode)
    }

    static func keyName(_ code: Int) -> String {
        let special: [Int: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
            65: ".", 67: "*", 69: "+", 71: "Clear", 75: "/", 76: "Enter",
            78: "−", 81: "=", 82: "0", 83: "1", 84: "2", 85: "3", 86: "4",
            87: "5", 88: "6", 89: "7", 91: "8", 92: "9", 96: "F5", 97: "F6",
            98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13",
            106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
            114: "Help", 115: "Home", 116: "Page Up", 117: "⌦", 118: "F4",
            119: "End", 120: "F2", 121: "Page Down", 122: "F1", 123: "←",
            124: "→", 125: "↓", 126: "↑"
        ]
        if let value = special[code] { return value }
        // Use the active keyboard layout for ordinary characters (including non-US layouts).
        if let input = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let raw = TISGetInputSourceProperty(input, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
            if let bytes = CFDataGetBytePtr(data) {
                let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 8)
                let status = UCKeyTranslate(layout, UInt16(clamping: code), UInt16(kUCKeyActionDisplay), 0,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                    characters.count, &length, &characters)
                if status == noErr && length > 0 {
                    let value = String(utf16CodeUnits: characters, count: length)
                    if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value.uppercased() }
                }
            }
        }
        let fallback: [Int: String] = [0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`"]
        return fallback[code] ?? "Key \(code)"
    }
}
