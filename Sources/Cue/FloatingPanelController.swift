import AppKit
import SwiftUI

extension Notification.Name {
    static let cueModalInteractionEnded = Notification.Name("CueModalInteractionEnded")
}

extension NSSavePanel {
    /// Cue-owned synchronous modal entry point. `runModal()` exposes no end
    /// notification, so this wrapper provides the controller a reliable,
    /// event-owned rearm without polling global input state.
    func runModalForCue() -> NSApplication.ModalResponse {
        defer { NotificationCenter.default.post(name: .cueModalInteractionEnded, object: self) }
        return self.runModal()
    }
}

final class CuePanel: NSPanel {
    var onRequestHide: (() -> Void)?
    var onExplicitInteraction: (() -> Void)?
    var onMouseButtonState: ((Bool) -> Void)?
    var isRetracted = false

    override var canBecomeKey: Bool { !isRetracted }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onRequestHide?()
    }

    override func performClose(_ sender: Any?) {
        onRequestHide?()
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if isRetracted {
                onExplicitInteraction?()
                return
            }
            onMouseButtonState?(true)
            if !isKeyWindow { onExplicitInteraction?() }
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            onMouseButtonState?(false)
        default:
            break
        }
        super.sendEvent(event)
    }
}

final class PanelTrackingHostingView: NSHostingView<PanelRootView> {
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    private var activeTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let activeTrackingArea { removeTrackingArea(activeTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        activeTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { onPointerEntered?() }
    override func mouseExited(with event: NSEvent) { onPointerExited?() }
}

/// The sole owner of CuePanel visibility, frame and presentation state.
/// Retraction changes this same panel into an in-bounds edge rail; no overlay,
/// global pointer monitor or second persisted placement is involved.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private static let initialSize = NSSize(width: 372, height: 600)
    private static let hoverRevealDelay = 0.14
    private static let retractDelay = 0.68
    private let panel: CuePanel
    private let chrome = PanelChromeModel()
    private let savedFrameKey = "CuePanelFrame"
    private var machine = PanelPresentationMachine()
    private var expandedFrame = NSRect(origin: .zero, size: initialSize)
    private var pendingRailPlacement: PanelRailPlacement?
    private var pendingWorkItem: DispatchWorkItem?
    private var isAnimating = false
    private var animationGeneration = 0
    private var pointerInside = false
    private var mouseButtonDown = false
    private var configuredFloating = true
    private var lastRevealReason: PanelRevealReason = .explicit
    private var focusComposerAfterReveal = false

    init(model: AppModel) {
        panel = CuePanel(
            contentRect: NSRect(origin: .zero, size: Self.initialSize),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        configuredFloating = model.settings.keepPanelOnTop
        panel.isFloatingPanel = true
        panel.level = configuredFloating ? .floating : .normal
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
        configureExpandedPanel()
        panel.delegate = self

        let root = PanelRootView(model: model, chrome: chrome)
        let hosting = PanelTrackingHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.onPointerEntered = { [weak self] in self?.pointerEntered() }
        hosting.onPointerExited = { [weak self] in self?.pointerExited() }
        panel.contentView = hosting

        expandedFrame = restoredOrDefaultFrame()
        panel.setFrame(expandedFrame, display: false)
        panel.onRequestHide = { [weak self] in self?.hide() }
        panel.onExplicitInteraction = { [weak self] in self?.show() }
        panel.onMouseButtonState = { [weak self] down in self?.mouseButtonChanged(down) }
        chrome.onExplicitReveal = { [weak self] in self?.show() }

        _ = process(.setPinned(model.settings.panelPinned))
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(interactionEnded),
            name: NSWindow.didEndSheetNotification,
            object: panel
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(interactionEnded),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(interactionEnded),
            name: .cueModalInteractionEnded,
            object: nil
        )
    }

    deinit {
        pendingWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    var isVisible: Bool { machine.state != .hidden }

    func toggle(focusComposer: Bool = false) {
        focusComposerAfterReveal = focusComposer
        _ = process(.toggle)
    }

    func show(focusComposer: Bool = false) {
        focusComposerAfterReveal = focusComposer
        _ = process(.show(reason: .explicit))
    }

    func hide() {
        focusComposerAfterReveal = false
        mouseButtonDown = false
        _ = process(.hide)
    }

    func setFloating(_ floating: Bool) {
        configuredFloating = floating
        guard machine.state == .expanded, lastRevealReason != .hover else { return }
        panel.level = floating ? .floating : .normal
    }

    func setPanelPinned(_ pinned: Bool) {
        guard machine.isPinned != pinned else { return }
        let wasAnimating = isAnimating
        let effects = process(.setPinned(pinned))
        let ownsAReplacementTransition = effects.contains { effect in
            if case .presentExpanded = effect { return true }
            if case .presentRetracted = effect { return true }
            if case .orderOut = effect { return true }
            return false
        }
        let hoverNeedsLevelNormalization = pinned && lastRevealReason == .hover && machine.state == .expanded
        if !ownsAReplacementTransition, machine.state == .expanded,
           wasAnimating || hoverNeedsLevelNormalization {
            // Pin changes invalidate the reducer generation. Retarget the
            // interrupted frame animation so its stale completion cannot leave
            // transition size constraints or isAnimating latched.
            presentExpanded(reason: hoverNeedsLevelNormalization ? .pin : lastRevealReason)
        } else if !pinned, !isAnimating {
            reconcilePointerAfterMovement()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        cancelPendingWork()
    }

    func windowDidResignKey(_ notification: Notification) {
        reconcilePointerAfterMovement()
    }

    func windowWillMove(_ notification: Notification) {
        cancelPendingWork()
    }

    func windowDidMove(_ notification: Notification) {
        saveExpandedFrameIfUserDriven()
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        cancelPendingWork()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveExpandedFrameIfUserDriven()
        reconcilePointerAfterMovement()
    }

    @discardableResult
    private func process(_ event: PanelPresentationEvent) -> [PanelPresentationEffect] {
        let effects = machine.handle(event)
        // A rail hides immediately rather than briefly exposing the retained
        // 352pt Sidecar subtree inside a 22pt window during a fade-out.
        if machine.state != .hidden || !panel.isRetracted { chrome.state = machine.state }
        for effect in effects { apply(effect) }
        return effects
    }

    private func apply(_ effect: PanelPresentationEffect) {
        switch effect {
        case .cancelPending:
            cancelPendingWork()
        case let .presentExpanded(reason):
            presentExpanded(reason: reason)
        case .presentRetracted:
            presentRetracted()
        case .orderOut:
            orderOut()
        case let .scheduleHoverReveal(token):
            schedule(after: Self.hoverRevealDelay) { [weak self] in
                _ = self?.process(.hoverRevealDeadline(token: token))
            }
        case let .scheduleRetraction(token):
            schedule(after: Self.retractDelay) { [weak self] in
                self?.retractionDeadline(token: token)
            }
        }
    }

    private func presentExpanded(reason: PanelRevealReason) {
        let token = machine.generation
        lastRevealReason = reason
        pendingRailPlacement = nil
        preparePanelForTransition()
        panel.isRetracted = false
        panel.level = reason.usesTemporaryFloatingLevel ? .floating : (configuredFloating ? .floating : .normal)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        transitionFrame(to: expandedFrame, duration: 0.16, token: token) { [weak self] in
            guard let self, self.machine.state == .expanded else { return }
            self.configureExpandedPanel()
            self.finishExplicitFocusIfNeeded(reason: reason)
            self.reconcilePointerAfterMovement()
        }
    }

    private func presentRetracted() {
        guard case let .retracted(edge) = machine.state,
              let placement = pendingRailPlacement, placement.edge == edge else { return }
        let token = machine.generation
        focusComposerAfterReveal = false
        preparePanelForTransition()
        panel.isRetracted = true
        panel.level = .floating
        panel.orderFrontRegardless()
        transitionFrame(to: placement.frame, duration: 0.17, token: token) { [weak self] in
            guard let self, case .retracted = self.machine.state else { return }
            self.configureRetractedPanel()
            self.reconcilePointerAfterMovement()
        }
    }

    private func orderOut() {
        pendingRailPlacement = nil
        guard panel.isVisible else { return }
        interruptPhysicalAnimation()
        animationGeneration &+= 1
        let animationToken = animationGeneration
        if panel.isRetracted || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
            panel.alphaValue = 1
            isAnimating = false
            chrome.state = .hidden
            return
        }
        interruptPhysicalAnimation()
        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      animationToken == self.animationGeneration,
                      self.machine.state == .hidden else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.isAnimating = false
                self.chrome.state = .hidden
            }
        }
    }

    private func finishExplicitFocusIfNeeded(reason: PanelRevealReason) {
        guard reason.allowsFocus else { return }
        panel.makeKey()
        if focusComposerAfterReveal {
            focusComposerAfterReveal = false
            let token = machine.generation
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.machine.generation, self.machine.state == .expanded else { return }
                NotificationCenter.default.post(name: .cueFocusComposer, object: nil)
            }
        }
    }

    private func transitionFrame(
        to target: NSRect,
        duration: TimeInterval,
        token: Int,
        completion: @escaping () -> Void
    ) {
        interruptPhysicalAnimation()
        animationGeneration &+= 1
        let animationToken = animationGeneration
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || panel.frame.equalTo(target) {
            isAnimating = true
            panel.setFrame(target, display: true)
            isAnimating = false
            completion()
            return
        }
        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      token == self.machine.generation,
                      animationToken == self.animationGeneration else { return }
                self.panel.setFrame(target, display: true)
                self.isAnimating = false
                completion()
            }
        }
    }

    private func pointerEntered() {
        pointerInside = true
        guard !isAnimating else { return }
        _ = process(.hoverEntered)
    }

    private func pointerExited() {
        pointerInside = false
        guard !isAnimating else { return }
        _ = process(.hoverExited)
    }

    private func mouseButtonChanged(_ down: Bool) {
        mouseButtonDown = down
        if down {
            cancelPendingWork()
        } else {
            reconcilePointerAfterMovement()
        }
    }

    private func retractionDeadline(token: Int) {
        guard token == machine.generation, machine.state == .expanded else { return }
        guard canAutoRetract else {
            return
        }
        let placement = PanelGeometryPolicy.railPlacement(for: expandedFrame, screens: screenGeometries)
        pendingRailPlacement = placement
        _ = process(.retractDeadline(token: token, edge: placement?.edge))
    }

    private var canAutoRetract: Bool {
        !machine.isPinned &&
            !pointerInside &&
            !panel.isKeyWindow &&
            !panel.inLiveResize &&
            panel.attachedSheet == nil &&
            NSApp.modalWindow == nil &&
            !mouseButtonDown
    }

    private func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        cancelPendingWork()
        let item = DispatchWorkItem(block: action)
        pendingWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelPendingWork() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }

    private func interruptPhysicalAnimation() {
        guard isAnimating else { return }
        animationGeneration &+= 1
        // A direct assignment retargets AppKit's frame/alpha animators. Old
        // completion handlers remain token-guarded and cannot mutate state.
        let currentFrame = panel.frame
        let currentAlpha = panel.alphaValue
        panel.setFrame(currentFrame, display: true)
        panel.alphaValue = currentAlpha
        isAnimating = false
    }

    private func reconcilePointerAfterMovement() {
        pointerInside = panel.frame.contains(NSEvent.mouseLocation)
        switch machine.state {
        case .retracted where pointerInside:
            _ = process(.hoverEntered)
        case .expanded where !pointerInside && !panel.isKeyWindow:
            _ = process(.hoverExited)
        default:
            break
        }
    }

    private func configureExpandedPanel() {
        panel.styleMask.insert(.resizable)
        panel.contentMinSize = PanelGeometryPolicy.minimumExpandedSize
        panel.contentMaxSize = PanelGeometryPolicy.maximumExpandedSize
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
    }

    private func preparePanelForTransition() {
        panel.contentMinSize = .zero
        panel.contentMaxSize = NSSize(width: 10_000, height: 10_000)
        panel.styleMask.remove(.resizable)
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
    }

    private func configureRetractedPanel() {
        panel.styleMask.remove(.resizable)
        panel.contentMinSize = PanelGeometryPolicy.railSize
        panel.contentMaxSize = PanelGeometryPolicy.railSize
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
    }

    private func saveExpandedFrameIfUserDriven() {
        guard machine.state == .expanded, !isAnimating,
              panel.frame.width >= PanelGeometryPolicy.minimumExpandedSize.width,
              panel.frame.height >= PanelGeometryPolicy.minimumExpandedSize.height,
              let repaired = PanelGeometryPolicy.repairExpandedFrame(panel.frame, screens: screenGeometries) else { return }
        expandedFrame = repaired
        UserDefaults.standard.set(NSStringFromRect(repaired), forKey: savedFrameKey)
    }

    private func restoredOrDefaultFrame() -> NSRect {
        if let value = UserDefaults.standard.string(forKey: savedFrameKey),
           let repaired = PanelGeometryPolicy.repairExpandedFrame(NSRectFromString(value), screens: screenGeometries) {
            return repaired
        }
        guard let screen = NSScreen.main else { return NSRect(origin: .zero, size: Self.initialSize) }
        let visible = screen.visibleFrame
        let candidate = NSRect(
            x: visible.maxX - Self.initialSize.width - 16,
            y: visible.maxY - Self.initialSize.height - 16,
            width: Self.initialSize.width,
            height: Self.initialSize.height
        )
        return PanelGeometryPolicy.repairExpandedFrame(candidate, screens: screenGeometries) ?? candidate
    }

    @objc private func screenParametersChanged() {
        guard let repaired = PanelGeometryPolicy.repairExpandedFrame(expandedFrame, screens: screenGeometries) else {
            // If macOS is transiently reporting no usable display, preserve the
            // last canonical frame and let the next parameters notification repair it.
            return
        }
        expandedFrame = repaired
        UserDefaults.standard.set(NSStringFromRect(repaired), forKey: savedFrameKey)
        switch machine.state {
        case .expanded:
            let token = machine.generation
            transitionFrame(to: repaired, duration: 0, token: token) { [weak self] in
                self?.configureExpandedPanel()
                self?.reconcilePointerAfterMovement()
            }
        case .retracted:
            guard let placement = PanelGeometryPolicy.railPlacement(for: repaired, screens: screenGeometries) else {
                _ = process(.show(reason: .pin))
                return
            }
            pendingRailPlacement = placement
            _ = process(.repairRetractedEdge(placement.edge))
            let token = machine.generation
            transitionFrame(to: placement.frame, duration: 0, token: token) { [weak self] in
                self?.configureRetractedPanel()
                self?.reconcilePointerAfterMovement()
            }
        case .hidden:
            panel.setFrame(repaired, display: false)
        }
    }

    @objc private func interactionEnded(_ notification: Notification) {
        mouseButtonDown = false
        guard !isAnimating else { return }
        reconcilePointerAfterMovement()
    }

    private var screenGeometries: [PanelScreenGeometry] {
        NSScreen.screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return PanelScreenGeometry(
                id: number?.stringValue ?? "screen-\(index)",
                frame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
    }
}
