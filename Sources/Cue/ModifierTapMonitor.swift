import AppKit

@MainActor
final class ModifierTapMonitor {
    var onDoubleTap: (() -> Void)?

    private var detector = ModifierTapDetector()
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        detector = ModifierTapDetector()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            detector.handleGestureBreak()
        case .flagsChanged:
            let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])
            let classified: ModifierTapDetector.ModifierEvent
            if flags == .shift {
                guard let side = shiftSide(for: event.keyCode) else {
                    detector.handleGestureBreak()
                    return
                }
                classified = .targetAlone(side: side)
            } else if flags.isEmpty {
                classified = .none
            } else {
                classified = .other(targetHeld: flags.contains(.shift))
            }
            if detector.handleModifiers(classified, timestamp: event.timestamp) { onDoubleTap?() }
        default:
            break
        }
    }

    private func shiftSide(for keyCode: UInt16) -> ModifierTapDetector.ShiftSide? {
        switch keyCode {
        case 56: .left
        case 60: .right
        default: nil
        }
    }
}
