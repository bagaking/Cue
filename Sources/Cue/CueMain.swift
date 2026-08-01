import AppKit
import Combine

@MainActor
final class CueApplicationDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var panelController: FloatingPanelController!
    private var settingsController: SettingsWindowController!
    private var statusController: StatusItemController!
    private var tapMonitor: ModifierTapMonitor!
    private var hotKeyCenter: GlobalHotKeyCenter!
    private var permissionSubscription: AnyCancellable?
    private var settingsSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        model = AppModel()
        panelController = FloatingPanelController(model: model)
        settingsController = SettingsWindowController(model: model)
        tapMonitor = ModifierTapMonitor()
        hotKeyCenter = GlobalHotKeyCenter()

        statusController = StatusItemController(
            onToggle: { [weak self] in self?.panelController.toggle() },
            onCapture: { [weak self] in self?.captureSelection() },
            onComposer: { [weak self] in self?.showComposer() },
            onArchive: { [weak self] in self?.showArchive() },
            onSettings: { [weak self] in self?.settingsController.show() },
            onReveal: { [weak self] in self?.model.revealWorkspace() }
        )

        model.onRequestSettings = { [weak self] in self?.settingsController.show() }
        model.onRequestComposer = { [weak self] in self?.showComposer() }
        model.onRequestHide = { [weak self] in self?.panelController.hide() }

        tapMonitor.onDoubleTap = { [weak self] in self?.captureSelection() }
        hotKeyCenter.setHandler(for: .capture) { [weak self] in self?.captureSelection() }
        hotKeyCenter.setHandler(for: .panel) { [weak self] in self?.panelController.toggle() }
        hotKeyCenter.setHandler(for: .composer) { [weak self] in self?.showComposer() }
        permissionSubscription = model.$isAccessibilityTrusted
            .removeDuplicates()
            .sink { [weak self] trusted in
                if trusted { self?.tapMonitor.start() } else { self?.tapMonitor.stop() }
            }

        if model.isAccessibilityTrusted { tapMonitor.start() }
        settingsSubscription = model.$settings
            .sink { [weak self] settings in
                self?.panelController?.setFloating(settings.keepPanelOnTop)
                self?.applyHotKeys(settings)
        }
        applyHotKeys(model.settings)
        if !model.hasWorkspace || ProcessInfo.processInfo.arguments.contains("--show") {
            panelController.show()
        }
        if ProcessInfo.processInfo.arguments.contains("--capture-selection") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.captureSelection()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tapMonitor?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func captureSelection() {
        switch SelectionCaptureService.read(settings: model.settings) {
        case let .selection(selection):
            let outcome = model.addCapturedSelection(selection)
            switch outcome {
            case .captured:
                CaptureHUD.show(message: "Captured · \(model.activeWorkspaceTitle)", symbolName: "checkmark.circle.fill")
                statusController.flash(symbol: "checkmark.circle.fill", description: "Captured")
            case .duplicate:
                CaptureHUD.show(message: "Already captured", symbolName: "equal.circle.fill")
                statusController.flash(symbol: "equal.circle", description: "Duplicate not added")
            case let .storageFailure(message):
                CaptureHUD.show(message: "Not saved · \(message)", symbolName: "externaldrive.badge.exclamationmark", isError: true)
            default:
                CaptureHUD.show(message: "Nothing captured", symbolName: "xmark.circle", isError: true)
            }
        case .permissionMissing:
            model.publishReceipt(Receipt(
                message: "Selection access is off",
                symbol: "hand.raised.fill",
                actionTitle: "Settings",
                action: .openSettings,
                isError: true
            ))
            CaptureHUD.show(message: "Selection access is off · typed capture still works", symbolName: "hand.raised.fill", isError: true)
            panelController.show()
        case .secureField:
            CaptureHUD.show(message: "Not captured from secure fields", symbolName: "lock.shield.fill", isError: true)
            statusController.flash(symbol: "lock.shield", description: "Secure field not captured")
        case let .denylisted(appName):
            CaptureHUD.show(message: "Not captured from \(appName)", symbolName: "hand.raised.slash.fill", isError: true)
        case .nothingSelected:
            model.publishReceipt(Receipt(
                message: "Nothing readable selected",
                symbol: "text.badge.xmark",
                actionTitle: "Type instead",
                action: .openComposer,
                isError: true
            ))
            CaptureHUD.show(message: "Nothing readable selected · open Cue to type", symbolName: "text.badge.xmark", isError: true)
            statusController.flash(symbol: "xmark.circle", description: "Nothing selected")
        case .unavailable:
            CaptureHUD.show(message: "Selection unavailable", symbolName: "exclamationmark.circle", isError: true)
        }
    }

    private func showComposer() {
        model.showingArchive = false
        model.clearSelection()
        panelController.show(focusComposer: true)
    }

    private func showArchive() {
        model.showingArchive = true
        model.clearSelection()
        panelController.show()
    }

    private func applyHotKeys(_ settings: AppSettings) {
        let bindings: [(GlobalHotKeyCenter.HotKeyID, String, String)] = [
            (.capture, settings.captureChord, "Capture"),
            (.panel, settings.panelChord, "Show/hide"),
            (.composer, settings.composerChord, "Composer"),
        ]
        for (id, rawValue, name) in bindings {
            let chord = GlobalShortcutPreset(rawValue: rawValue)?.chord
            if hotKeyCenter.arm(id, chord: chord) == .failed {
                CaptureHUD.show(
                    message: "\(name) shortcut is already in use",
                    symbolName: "keyboard.badge.exclamationmark",
                    isError: true
                )
                model.publishReceipt(Receipt(
                    message: "\(name) shortcut is already in use",
                    symbol: "keyboard.badge.exclamationmark",
                    actionTitle: "Settings",
                    action: .openSettings,
                    isError: true
                ))
            }
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Cue", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ","))
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Cue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsFromMenu() { settingsController?.show() }
}

@main
enum CueMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        if ProcessInfo.processInfo.arguments.contains("--render-preview") {
            app.setActivationPolicy(.prohibited)
            let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist", isDirectory: true)
            do {
                try PreviewRenderer.renderAll(outputDirectory: output)
                print(output.path)
            } catch {
                fputs("Cue preview failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--integration-checks") {
            app.setActivationPolicy(.prohibited)
            exit(IntegrationCheckRunner.run())
        }
        let delegate = CueApplicationDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
