import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onToggle: () -> Void
    private let onCapture: () -> Void
    private let onComposer: () -> Void
    private let onArchive: () -> Void
    private let onSettings: () -> Void
    private let onReveal: () -> Void
    private var flashTask: Task<Void, Never>?

    init(
        onToggle: @escaping () -> Void,
        onCapture: @escaping () -> Void,
        onComposer: @escaping () -> Void,
        onArchive: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onReveal: @escaping () -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.onToggle = onToggle
        self.onCapture = onCapture
        self.onComposer = onComposer
        self.onArchive = onArchive
        self.onSettings = onSettings
        self.onReveal = onReveal
        super.init()

        if let button = statusItem.button {
            button.image = normalImage
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Cue — next-thought queue"
        }
    }

    var button: NSStatusBarButton? { statusItem.button }

    func flash(symbol: String, description: String) {
        guard let button = statusItem.button else { return }
        flashTask?.cancel()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        flashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled else { return }
            self?.statusItem.button?.image = self?.normalImage
        }
    }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let secondary = event?.type == .rightMouseUp ||
            (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)
        if secondary { showMenu() } else { onToggle() }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(item("Show Cue", action: #selector(togglePanel), key: ""))
        menu.addItem(item("New Prompt", action: #selector(openComposer), key: "n"))
        menu.addItem(item("Capture Selection", action: #selector(captureSelection), key: ""))
        menu.addItem(.separator())
        menu.addItem(item("Open Archive", action: #selector(openArchive), key: ""))
        menu.addItem(item("Reveal Workspace in Finder", action: #selector(revealWorkspace), key: ""))
        menu.addItem(item("Settings…", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        let privacy = NSMenuItem(title: "No account · no telemetry · no passive capture", action: nil, keyEquivalent: "")
        privacy.isEnabled = false
        menu.addItem(privacy)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Cue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        guard let button = statusItem.button, let window = button.window else { return }
        button.highlight(true)
        menu.popUp(positioning: nil, at: NSPoint(x: window.frame.minX, y: window.frame.minY - 8), in: nil)
        button.highlight(false)
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func togglePanel() { onToggle() }
    @objc private func captureSelection() { onCapture() }
    @objc private func openComposer() { onComposer() }
    @objc private func openArchive() { onArchive() }
    @objc private func openSettings() { onSettings() }
    @objc private func revealWorkspace() { onReveal() }

    private var normalImage: NSImage? {
        NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: "Cue")
    }
}
