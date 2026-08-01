import AppKit
import Carbon.HIToolbox
import Foundation

/// Adapted from Pewter's MIT-licensed process-wide Carbon hotkey owner.
/// Carbon registration needs no Input Monitoring permission and reports
/// conflicts instead of leaving configured shortcuts silently dead.
@MainActor
final class GlobalHotKeyCenter {
    enum HotKeyID: UInt32 { case capture = 1, panel = 2, composer = 3 }

    struct Chord: Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
    }

    enum ArmResult { case unchanged, applied, failed }

    private static let signature = OSType(0x4355_4531) // CUE1
    private var handlers: [UInt32: () -> Void] = [:]
    private var registrations: [UInt32: (Chord, EventHotKeyRef)] = [:]
    private var eventHandler: EventHandlerRef?

    deinit {
        for registration in registrations.values { UnregisterEventHotKey(registration.1) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func setHandler(for id: HotKeyID, _ handler: @escaping () -> Void) {
        handlers[id.rawValue] = handler
    }

    func arm(_ id: HotKeyID, chord: Chord?) -> ArmResult {
        let current = registrations[id.rawValue]
        if current?.0 == chord { return .unchanged }
        if let current {
            UnregisterEventHotKey(current.1)
            registrations[id.rawValue] = nil
        }
        guard let chord else { return .applied }
        guard installHandlerIfNeeded() else { return .failed }

        if let reference = register(id, chord: chord) {
            registrations[id.rawValue] = (chord, reference)
            return .applied
        }

        if let current, let restored = register(id, chord: current.0) {
            registrations[id.rawValue] = (current.0, restored)
        }
        return .failed
    }

    private func register(_ id: HotKeyID, chord: Chord) -> EventHotKeyRef? {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            chord.keyCode,
            chord.modifiers,
            EventHotKeyID(signature: Self.signature, id: id.rawValue),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr else { return nil }
        return reference
    }

    private func installHandlerIfNeeded() -> Bool {
        guard eventHandler == nil else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                var identifier = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard result == noErr, identifier.signature == GlobalHotKeyCenter.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                return MainActor.assumeIsolated {
                    guard let handler = center.handlers[identifier.id] else { return OSStatus(eventNotHandledErr) }
                    handler()
                    return noErr
                }
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )
        return status == noErr
    }
}

enum GlobalShortcutPreset: String, CaseIterable, Identifiable {
    case off
    case controlShiftC
    case controlOptionC
    case controlShiftSpace
    case controlOptionSpace
    case controlShiftP

    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off"
        case .controlShiftC: "⌃⇧C"
        case .controlOptionC: "⌃⌥C"
        case .controlShiftSpace: "⌃⇧Space"
        case .controlOptionSpace: "⌃⌥Space"
        case .controlShiftP: "⌃⇧P"
        }
    }

    var chord: GlobalHotKeyCenter.Chord? {
        switch self {
        case .off: nil
        case .controlShiftC: .init(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | shiftKey))
        case .controlOptionC: .init(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey))
        case .controlShiftSpace: .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | shiftKey))
        case .controlOptionSpace: .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
        case .controlShiftP: .init(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | shiftKey))
        }
    }
}
