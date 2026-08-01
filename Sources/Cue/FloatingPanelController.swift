import AppKit
import SwiftUI

final class CuePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    override func sendEvent(_ event: NSEvent) {
        if !isKeyWindow, event.type == .leftMouseDown || event.type == .rightMouseDown {
            makeKey()
        }
        super.sendEvent(event)
    }
}

/// Combines Pewter's nonactivating panel with Nickel's generation-safe
/// animation and disconnected-display frame repair.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private static let minimumSize = NSSize(width: 352, height: 500)
    private static let maximumSize = NSSize(width: 560, height: 900)
    private let panel: CuePanel
    private var toggleGeneration = 0
    private var isAnimating = false
    private let savedFrameKey = "CuePanelFrame"

    init(model: AppModel) {
        panel = CuePanel(
            contentRect: NSRect(x: 0, y: 0, width: 372, height: 600),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = model.settings.keepPanelOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "Cue"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentMinSize = Self.minimumSize
        panel.contentMaxSize = Self.maximumSize
        panel.delegate = self

        let hosting = NSHostingView(rootView: SidecarView(model: model).ignoresSafeArea(.container, edges: .top))
        hosting.sizingOptions = []
        panel.contentView = hosting

        restoreOrPosition()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    var isVisible: Bool { panel.isVisible }

    func toggle(focusComposer: Bool = false) {
        if panel.isVisible { hide() } else { show(focusComposer: focusComposer) }
    }

    func show(focusComposer: Bool = false) {
        toggleGeneration += 1
        let generation = toggleGeneration
        repairFrameIfNeeded()

        let target = panel.frame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            panel.makeKey()
        } else {
            isAnimating = true
            var start = target
            start.origin.x += 8
            panel.setFrame(start, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panel.makeKey()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(target, display: true)
            } completionHandler: { [weak self] in
                DispatchQueue.main.async {
                    guard let self, generation == self.toggleGeneration else { return }
                    self.isAnimating = false
                }
            }
        }

        if focusComposer {
            DispatchQueue.main.async { NotificationCenter.default.post(name: .cueFocusComposer, object: nil) }
        } else {
            panel.makeFirstResponder(panel.contentView)
        }
    }

    func hide() {
        toggleGeneration += 1
        let generation = toggleGeneration
        guard panel.isVisible else { return }
        let resting = panel.frame
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
            return
        }
        isAnimating = true
        var end = resting
        end.origin.x += 8
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(end, display: true)
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self, generation == self.toggleGeneration else { return }
                self.panel.orderOut(nil)
                self.panel.setFrame(resting, display: false)
                self.panel.alphaValue = 1
                self.isAnimating = false
            }
        }
    }

    func setFloating(_ floating: Bool) {
        panel.level = floating ? .floating : .normal
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { saveFrame() }

    private func saveFrame() {
        guard !isAnimating else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: savedFrameKey)
    }

    private func restoreOrPosition() {
        if let value = UserDefaults.standard.string(forKey: savedFrameKey) {
            let frame = NSRectFromString(value)
            if let clamped = clamp(frame) {
                panel.setFrame(clamped, display: false)
                return
            }
        }
        positionNearEdge()
    }

    private func positionNearEdge() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 16, y: visible.maxY - panel.frame.height - 16))
    }

    private func clamp(_ frame: NSRect) -> NSRect? {
        guard frame.width >= Self.minimumSize.width, frame.height >= Self.minimumSize.height,
              let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) else { return nil }
        let visible = screen.visibleFrame
        var value = frame
        value.size.width = min(max(value.width, Self.minimumSize.width), min(Self.maximumSize.width, visible.width))
        value.size.height = min(max(value.height, Self.minimumSize.height), min(Self.maximumSize.height, visible.height))
        value.origin.x = min(max(value.minX, visible.minX + 8), visible.maxX - value.width - 8)
        value.origin.y = min(max(value.minY, visible.minY + 8), visible.maxY - value.height - 8)
        return value
    }

    private func repairFrameIfNeeded() {
        if let clamped = clamp(panel.frame) {
            panel.setFrame(clamped, display: false)
        } else {
            panel.setContentSize(NSSize(width: 372, height: 600))
            positionNearEdge()
        }
    }

    @objc private func screenParametersChanged() { repairFrameIfNeeded() }
}
