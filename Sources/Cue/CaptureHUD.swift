import AppKit

/// Plain-AppKit nonactivating receipt adapted from Nickel's MIT-licensed HUD.
/// A new window is created for every receipt to avoid SwiftUI ViewBridge
/// ordering failures in transient status-level panels.
@MainActor
enum CaptureHUD {
    private static var current: HUDInstance?

    static func show(message: String, symbolName: String, isError: Bool = false) {
        current?.dismissImmediately()
        let instance = HUDInstance()
        current = instance
        instance.onFinished = { [weak instance] in
            if current === instance { current = nil }
        }
        instance.show(message: message, symbolName: symbolName, isError: isError)
    }
}

@MainActor
private final class HUDInstance {
    private final class HUDPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private var panel: HUDPanel?
    private var hideWorkItem: DispatchWorkItem?
    var onFinished: (() -> Void)?

    func show(message: String, symbolName: String, isError: Bool) {
        let content = HUDContentView(message: message, symbolName: symbolName, isError: isError)
        let panel = HUDPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: content.fittingSize.width, height: 40)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.panel = panel
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = content
        position(panel)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }

        let work = DispatchWorkItem { [weak self] in self?.fadeOutAndClose() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: work)
    }

    func dismissImmediately() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        close()
    }

    private func fadeOutAndClose() {
        guard let panel else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            close()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async { self?.close() }
        }
    }

    private func close() {
        guard let panel else { return }
        self.panel = nil
        panel.orderOut(nil)
        panel.close()
        onFinished?()
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 22
        // Put the receipt on the opposite side from the user's pointer and
        // likely text selection, reducing the chance that feedback obscures
        // the captured range.
        let x = mouse.x > visible.midX
            ? visible.minX + margin
            : visible.maxX - panel.frame.width - margin
        panel.setFrameOrigin(NSPoint(x: x, y: visible.maxY - panel.frame.height - margin))
    }
}

private final class HUDContentView: NSView {
    init(message: String, symbolName: String, isError: Bool) {
        super.init(frame: .zero)

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        icon.contentTintColor = isError ? .systemOrange : .controlAccentColor
        icon.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.cornerRadius = bounds.height / 2
        layer?.masksToBounds = true
    }
}
