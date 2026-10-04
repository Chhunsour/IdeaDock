import AppKit
import Carbon

enum HotKeyError: LocalizedError {
    case unavailable(OSStatus)
    case conflict(String)
    case invalidShortcut

    var errorDescription: String? {
        switch self {
        case .unavailable(let status): "The global shortcut could not be registered (macOS error \(status))."
        case .conflict(let label): "\(label) is already used by another shortcut. Choose a different combination."
        case .invalidShortcut: "Use Command, Option, or Control with a key."
        }
    }
}

/// Carbon hotkeys receive only the shortcuts we register. No event tap or input monitoring is used.
@MainActor final class HotKeyService {
    private struct Registration {
        let reference: EventHotKeyRef
        let keyCode: UInt32
        let modifiers: UInt32
        let action: () -> Void
    }

    private let signature: OSType = 0x49444F43 // IDOC
    private var registrations: [UInt32: Registration] = [:]
    private var handler: EventHandlerRef?
    private var installationStatus: OSStatus = noErr

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        installationStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return status }
            let service = Unmanaged<HotKeyService>.fromOpaque(context).takeUnretainedValue()
            let id = identifier.id
            let signature = identifier.signature
            Task { @MainActor in
                guard signature == service.signature else { return }
                service.registrations[id]?.action()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) throws {
        guard installationStatus == noErr else { throw HotKeyError.unavailable(installationStatus) }
        guard keyCode <= 127, let cleaned = ShortcutDisplay.validModifiers(Int(modifiers)) else { throw HotKeyError.invalidShortcut }
        let modifiers = UInt32(cleaned)
        let label = ShortcutDisplay.label(keyCode: Int(keyCode), modifiers: Int(modifiers))
        if registrations.contains(where: { $0.key != id && $0.value.keyCode == keyCode && $0.value.modifiers == modifiers }) {
            throw HotKeyError.conflict(label)
        }
        if let current = registrations[id], current.keyCode == keyCode && current.modifiers == modifiers {
            registrations[id] = Registration(reference: current.reference, keyCode: keyCode, modifiers: modifiers, action: action)
            return
        }
        // Keep the previous shortcut active unless the replacement registers successfully.
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &reference)
        guard status == noErr, let reference else {
            if status == OSStatus(eventHotKeyExistsErr) { throw HotKeyError.conflict(label) }
            throw HotKeyError.unavailable(status)
        }
        unregister(id: id)
        registrations[id] = Registration(reference: reference, keyCode: keyCode, modifiers: modifiers, action: action)
    }

    func unregister(id: UInt32) {
        if let entry = registrations.removeValue(forKey: id) { UnregisterEventHotKey(entry.reference) }
    }

    func unregisterAll() {
        for registration in registrations.values { UnregisterEventHotKey(registration.reference) }
        registrations.removeAll()
    }

    deinit {
        for registration in registrations.values { UnregisterEventHotKey(registration.reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
