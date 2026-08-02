import AppKit
import SwiftUI

private func currentAppKitPointerLocation() -> NSPoint? {
    guard let quartzPoint = CGEvent(source: nil)?.location,
          let primaryScreen = NSScreen.screens.first else { return nil }
    return NSPoint(x: quartzPoint.x, y: primaryScreen.frame.maxY - quartzPoint.y)
}

private func currentAppKitMouseButtonDown() -> Bool {
    NSEvent.pressedMouseButtons != 0
}

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
    var onMouseButtonState: ((Bool, NSView?) -> Void)?
    var onTextInputActivity: (() -> Void)?
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
            onExplicitInteraction?()
            onMouseButtonState?(true, editableTextTarget(at: event.locationInWindow))
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            onMouseButtonState?(false, editableTextTarget(at: event.locationInWindow))
        case .keyDown:
            onTextInputActivity?()
        default:
            break
        }
        super.sendEvent(event)
    }

    private func editableTextTarget(at point: NSPoint) -> NSView? {
        var candidate = contentView?.hitTest(point)
        while let view = candidate {
            if let textView = view as? NSTextView, textView.isEditable { return textView }
            if let textField = view as? NSTextField, textField.isEditable { return textField }
            candidate = view.superview
        }
        return nil
    }
}

final class PanelTrackingHostingView: NSHostingView<PanelRootView> {
    var onPointerEntered: ((NSEvent) -> Void)?
    var onPointerExited: ((NSEvent) -> Void)?
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

    override func mouseEntered(with event: NSEvent) { onPointerEntered?(event) }
    override func mouseExited(with event: NSEvent) { onPointerExited?(event) }
}

/// The sole owner of CuePanel visibility, frame and presentation state.
/// Retraction changes this same panel into an in-bounds edge rail; no overlay,
/// global pointer monitor or second persisted placement is involved.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private struct ActiveFrameAnimation {
        var startFrame: NSRect
        var targetFrame: NSRect
        var startedAt: TimeInterval
        var duration: TimeInterval
        var presentationToken: Int
        var animationToken: Int
        var completion: () -> Void
    }

    private struct FramePointerBaseline {
        var animationToken: Int
        var location: NSPoint?
    }

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
    private var frameAnimationTimer: Timer?
    private var activeFrameAnimation: ActiveFrameAnimation?
    private var pointerInside = false
    private var mouseButtonDown = false
    private var isMenuTracking = false
    private var isTextEditing = false
    private weak var activeTextEditor: NSView?
    private var configuredFloating = true
    private var lastRevealReason: PanelRevealReason = .explicit
    private var focusComposerAfterReveal = false
    private var composerFocusGeneration = 0
    private let panelTraceEnabled = ProcessInfo.processInfo.environment["CUE_PANEL_TRACE"] == "1"
    private let pointerLocationProvider: () -> NSPoint?
    private let mouseButtonStateProvider: () -> Bool
    private var trackingEventFence: TimeInterval = 0
    private var frameSettlePointerLocation: NSPoint?
    private var requiresPhysicalMotionAfterFrameSettle = false
    private var frameTransitionPointerBaseline: FramePointerBaseline?

    init(
        model: AppModel,
        pointerLocationProvider: @escaping () -> NSPoint? = currentAppKitPointerLocation,
        mouseButtonStateProvider: @escaping () -> Bool = currentAppKitMouseButtonDown
    ) {
        self.pointerLocationProvider = pointerLocationProvider
        self.mouseButtonStateProvider = mouseButtonStateProvider
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
        hosting.onPointerEntered = { [weak self] event in self?.pointerEntered(event) }
        hosting.onPointerExited = { [weak self] event in self?.pointerExited(event) }
        panel.contentView = hosting

        expandedFrame = restoredOrDefaultFrame()
        panel.setFrame(expandedFrame, display: false)
        panel.onRequestHide = { [weak self] in self?.hide() }
        panel.onExplicitInteraction = { [weak self] in self?.handleExplicitMouseInteraction() }
        panel.onMouseButtonState = { [weak self] down, editableTextTarget in
            self?.mouseButtonChanged(down, editableTextTarget: editableTextTarget)
        }
        panel.onTextInputActivity = { [weak self] in self?.textInputActivity() }
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
            selector: #selector(interactionBegan),
            name: NSMenu.didBeginTrackingNotification,
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textEditingBegan),
            name: NSText.didBeginEditingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textEditingEnded),
            name: NSText.didEndEditingNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        pendingWorkItem?.cancel()
        frameAnimationTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    var isVisible: Bool { machine.state != .hidden }

    func toggle(focusComposer: Bool = false) {
        invalidateComposerFocusRequest()
        focusComposerAfterReveal = focusComposer
        _ = process(.toggle)
    }

    func show(focusComposer: Bool = false) {
        invalidateComposerFocusRequest()
        focusComposerAfterReveal = focusComposer
        _ = process(.show(reason: .explicit))
    }

    func hide() {
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
        } else if !pinned {
            reconcileAfterTerminalEvent()
        }
    }

    private func handleExplicitMouseInteraction() {
        switch machine.state {
        case .hidden:
            show()
        case .retracted:
            revealFromRailClick()
        case .expanded where lastRevealReason == .hover:
            // Promote a hover preview before AppKit dispatches the click. This
            // restores configured level/key intent without moving away from
            // the rail that the user explicitly clicked.
            revealFromRailClick()
            panel.makeKey()
        case .expanded:
            break
        }
    }

    private func revealFromRailClick() {
        invalidateComposerFocusRequest()
        focusComposerAfterReveal = false
        _ = process(.show(reason: .railClick))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        cancelPendingWork()
        guard !focusComposerAfterReveal else { return }
        reconcileAfterTerminalEvent()
    }

    func windowDidResignKey(_ notification: Notification) {
        invalidateComposerFocusRequest()
        clearTextEditingHold()
        reconcileAfterTerminalEvent(releaseMouseButton: true)
    }

    func windowWillMove(_ notification: Notification) {
        cancelPendingWork()
    }

    func windowDidMove(_ notification: Notification) {
        saveExpandedFrameIfUserDriven()
        guard machine.state == .expanded, !isAnimating,
              mouseButtonDown, !mouseButtonStateProvider() else { return }
        // AppKit window dragging may consume the matching content mouse-up.
        // A did-move sample with no pressed button is the event-owned terminal
        // for that drag, not a poll or retry loop.
        reconcileAfterTerminalEvent(releaseMouseButton: true)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        cancelPendingWork()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveExpandedFrameIfUserDriven()
        reconcileAfterTerminalEvent(releaseMouseButton: true)
    }

    @discardableResult
    private func process(_ event: PanelPresentationEvent) -> [PanelPresentationEffect] {
        trace("event=\(String(describing: event)) before=\(String(describing: machine.state)) frame=\(NSStringFromRect(panel.frame))")
        let effects = machine.handle(event)
        if machine.state == .hidden { clearTransientEngagementForHiddenState() }
        // A rail hides immediately rather than briefly exposing the retained
        // 352pt Sidecar subtree inside a 22pt window during a fade-out.
        if machine.state != .hidden || !panel.isRetracted { chrome.state = machine.state }
        for effect in effects { apply(effect) }
        trace("event=\(String(describing: event)) after=\(String(describing: machine.state)) effects=\(String(describing: effects)) frame=\(NSStringFromRect(panel.frame))")
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
        let railPlacement = pendingRailPlacement
        let targetFrame = reason.usesRailAnchor
            ? railPlacement.map {
                PanelGeometryPolicy.hoverExpandedFrame(
                    canonicalExpandedFrame: expandedFrame,
                    railPlacement: $0
                )
            } ?? expandedFrame
            : expandedFrame
        // Hover keeps the originating rail available so a click can promote
        // that preview to an explicit, focused reveal without changing frame.
        if reason != .hover { pendingRailPlacement = nil }
        preparePanelForTransition()
        panel.isRetracted = false
        panel.level = reason.usesTemporaryFloatingLevel ? .floating : (configuredFloating ? .floating : .normal)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        transitionFrame(to: targetFrame, duration: 0.16, token: token) { [weak self] in
            guard let self, self.machine.state == .expanded else { return }
            self.configureExpandedPanel()
            let waitingForComposerFocus = self.finishExplicitFocusIfNeeded(reason: reason)
            if !waitingForComposerFocus { self.settlePointerAfterProgrammaticFrame() }
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
            self.settlePointerAfterProgrammaticFrame()
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

    private func finishExplicitFocusIfNeeded(reason: PanelRevealReason) -> Bool {
        guard reason.allowsFocus else { return false }
        if focusComposerAfterReveal { NSApp.activate() }
        panel.makeKey()
        if focusComposerAfterReveal {
            focusComposerAfterReveal = false
            let focusToken = animationGeneration
            composerFocusGeneration &+= 1
            let composerToken = composerFocusGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      focusToken == self.animationGeneration,
                      composerToken == self.composerFocusGeneration,
                      self.machine.state == .expanded,
                      self.panel.isKeyWindow,
                      NSApp.isActive else { return }
                NotificationCenter.default.post(name: .cueFocusComposer, object: nil)
                if !self.captureTextEditingHoldFromResponder(matching: nil) {
                    self.settlePointerAfterProgrammaticFrame()
                }
            }
            return true
        }
        return false
    }

    private func transitionFrame(
        to target: NSRect,
        duration: TimeInterval,
        token: Int,
        completion: @escaping () -> Void
    ) {
        trace("frame-transition start target=\(NSStringFromRect(target)) actual=\(NSStringFromRect(panel.frame))")
        interruptPhysicalAnimation()
        animationGeneration &+= 1
        let animationToken = animationGeneration
        frameTransitionPointerBaseline = FramePointerBaseline(
            animationToken: animationToken,
            location: pointerLocationProvider()
        )
        if duration <= 0 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || panel.frame.equalTo(target) {
            isAnimating = true
            panel.setFrame(target, display: true)
            trackingEventFence = ProcessInfo.processInfo.systemUptime
            isAnimating = false
            trace("frame-transition immediate target=\(NSStringFromRect(target)) actual=\(NSStringFromRect(panel.frame))")
            completion()
            return
        }
        isAnimating = true
        activeFrameAnimation = ActiveFrameAnimation(
            startFrame: panel.frame,
            targetFrame: target,
            startedAt: ProcessInfo.processInfo.systemUptime,
            duration: duration,
            presentationToken: token,
            animationToken: animationToken,
            completion: completion
        )
        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(frameAnimationTick),
            userInfo: nil,
            repeats: true
        )
        frameAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func frameAnimationTick(_ timer: Timer) {
        guard frameAnimationTimer === timer else {
            timer.invalidate()
            return
        }
        guard let animation = activeFrameAnimation,
              animation.presentationToken == machine.generation,
              animation.animationToken == animationGeneration else {
            timer.invalidate()
            frameAnimationTimer = nil
            activeFrameAnimation = nil
            isAnimating = false
            return
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - animation.startedAt
        let progress = min(max(elapsed / animation.duration, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        let frame = interpolate(from: animation.startFrame, to: animation.targetFrame, progress: eased)
        panel.setFrame(frame, display: true)

        guard progress >= 1 else { return }
        timer.invalidate()
        if frameAnimationTimer === timer { frameAnimationTimer = nil }
        activeFrameAnimation = nil
        panel.setFrame(animation.targetFrame, display: true)
        trackingEventFence = ProcessInfo.processInfo.systemUptime
        isAnimating = false
        trace("frame-transition complete target=\(NSStringFromRect(animation.targetFrame)) actual=\(NSStringFromRect(panel.frame))")
        animation.completion()
    }

    private func interpolate(from start: NSRect, to target: NSRect, progress: Double) -> NSRect {
        func value(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
            lhs + (rhs - lhs) * CGFloat(progress)
        }
        return NSRect(
            x: value(start.minX, target.minX),
            y: value(start.minY, target.minY),
            width: value(start.width, target.width),
            height: value(start.height, target.height)
        )
    }

    private func pointerEntered(_ event: NSEvent) {
        acceptTrackingEvent(.entered, timestamp: event.timestamp)
    }

    private func pointerExited(_ event: NSEvent) {
        acceptTrackingEvent(.exited, timestamp: event.timestamp)
    }

    private func acceptTrackingEvent(_ kind: PanelTrackingEventKind, timestamp: TimeInterval) {
        let actualPoint = pointerLocationProvider()
        let actualInside = actualPoint.map(panel.frame.contains)
        let actualMoved = actualPoint.flatMap { point in
            frameSettlePointerLocation.map { baseline in
                abs(point.x - baseline.x) > 0.5 || abs(point.y - baseline.y) > 0.5
            }
        }
        guard PanelTrackingPolicy.accepts(
            kind,
            eventTimestamp: timestamp,
            fence: trackingEventFence,
            isAnimating: isAnimating,
            actualPointerInside: actualInside,
            actualPointerMovedSinceSettle: actualMoved,
            requiresPhysicalMotionEvidence: requiresPhysicalMotionAfterFrameSettle
        ) else {
            trace("tracking-\(String(describing: kind)) ignored timestamp=\(timestamp) fence=\(trackingEventFence) actualInside=\(String(describing: actualInside)) actualMoved=\(String(describing: actualMoved))")
            return
        }
        frameSettlePointerLocation = actualPoint
        requiresPhysicalMotionAfterFrameSettle = false
        switch kind {
        case .entered:
            pointerInside = true
            _ = process(.hoverEntered)
        case .exited:
            pointerInside = false
            _ = process(.hoverExited)
        }
    }

    private func mouseButtonChanged(_ down: Bool, editableTextTarget: NSView?) {
        mouseButtonDown = down
        if down {
            if editableTextTarget != nil {
                NSApp.activate()
                panel.makeKey()
            } else {
                clearTextEditingHold()
            }
            cancelPendingWork()
        } else {
            if editableTextTarget != nil,
               captureTextEditingHoldFromResponder(matching: editableTextTarget) {
                return
            }
            reconcileAfterTerminalEvent()
        }
    }

    private func retractionDeadline(token: Int) {
        guard token == machine.generation, machine.state == .expanded else { return }
        trace("retract-deadline token=\(token) engagement=\(String(describing: engagementSnapshot))")
        guard canAutoRetract else {
            trace("retract-deadline suppressed")
            return
        }
        let placement = PanelGeometryPolicy.railPlacement(for: expandedFrame, screens: screenGeometries)
        trace("retract-deadline placement=\(String(describing: placement))")
        pendingRailPlacement = placement
        _ = process(.retractDeadline(token: token, edge: placement?.edge))
    }

    private var canAutoRetract: Bool {
        PanelEngagementPolicy.allowsAutoRetraction(engagementSnapshot)
    }

    private var engagementSnapshot: PanelEngagementSnapshot {
        PanelEngagementSnapshot(
            panelPinned: machine.isPinned,
            pointerInside: pointerInside,
            isKeyWindow: panel.isKeyWindow,
            isTextEditing: isTextEditing,
            mouseButtonDown: mouseButtonDown,
            isMenuTracking: isMenuTracking,
            isLiveResizing: panel.inLiveResize,
            hasAttachedSheet: panel.attachedSheet != nil,
            hasModalWindow: NSApp.modalWindow != nil
        )
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
        frameAnimationTimer?.invalidate()
        frameAnimationTimer = nil
        activeFrameAnimation = nil
        animationGeneration &+= 1
        // A direct assignment retargets AppKit's frame/alpha animators. Old
        // completion handlers remain token-guarded and cannot mutate state.
        let currentFrame = panel.frame
        let currentAlpha = panel.alphaValue
        panel.setFrame(currentFrame, display: true)
        panel.alphaValue = currentAlpha
        isAnimating = false
    }

    private func settlePointerAfterProgrammaticFrame() {
        trackingEventFence = ProcessInfo.processInfo.systemUptime
        requiresPhysicalMotionAfterFrameSettle = true
        let point = sampleCurrentPointerState()
        let transitionBaseline = frameTransitionPointerBaseline
        frameTransitionPointerBaseline = nil
        let shouldReplayRailEntry = transitionBaseline?.animationToken == animationGeneration &&
            PanelTrackingPolicy.shouldReplayRailEntry(
                transitionStartPointer: transitionBaseline?.location,
                settledPointer: point,
                railFrame: panel.frame
            )
        if case .retracted = machine.state, shouldReplayRailEntry {
            requiresPhysicalMotionAfterFrameSettle = false
            _ = process(.hoverEntered)
            return
        }
        rearmFromTrackedPointerState()
    }

    @discardableResult
    private func sampleCurrentPointerState() -> NSPoint? {
        let point = pointerLocationProvider()
        if let point {
            frameSettlePointerLocation = point
            pointerInside = panel.frame.contains(point)
        }
        return point
    }

    /// Existing interaction terminal owners call this once to release the
    /// fact they own, sample current pointer truth and arm the single existing
    /// generation-token deadline. It never polls and never retries a blocked
    /// deadline.
    private func reconcileAfterTerminalEvent(releaseMouseButton: Bool = false) {
        if releaseMouseButton { mouseButtonDown = false }
        guard !isAnimating else { return }
        _ = sampleCurrentPointerState()
        rearmFromTrackedPointerState()
    }

    /// Rearms only from pointer truth already accepted from local tracking or
    /// a one-shot post-transition Quartz sample. A retracted panel never
    /// manufactures rail entry merely because it moved under a still cursor.
    private func rearmFromTrackedPointerState() {
        switch machine.state {
        case .expanded where !pointerInside:
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
            let target = lastRevealReason.usesRailAnchor
                ? PanelGeometryPolicy.railPlacement(for: repaired, screens: screenGeometries).map {
                    PanelGeometryPolicy.hoverExpandedFrame(canonicalExpandedFrame: repaired, railPlacement: $0)
                } ?? repaired
                : repaired
            transitionFrame(to: target, duration: 0, token: token) { [weak self] in
                self?.configureExpandedPanel()
                self?.settlePointerAfterProgrammaticFrame()
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
                self?.settlePointerAfterProgrammaticFrame()
            }
        case .hidden:
            panel.setFrame(repaired, display: false)
        }
    }

    @objc private func interactionBegan(_ notification: Notification) {
        isMenuTracking = true
        cancelPendingWork()
    }

    @objc private func interactionEnded(_ notification: Notification) {
        if notification.name == NSMenu.didEndTrackingNotification { isMenuTracking = false }
        reconcileAfterTerminalEvent(releaseMouseButton: true)
    }

    @objc private func textEditingBegan(_ notification: Notification) {
        guard let editor = notification.object as? NSView, editor.window === panel else { return }
        activeTextEditor = editor
        isTextEditing = true
        cancelPendingWork()
    }

    @objc private func textEditingEnded(_ notification: Notification) {
        guard let editor = notification.object as? NSView,
              activeTextEditor === editor || editor.window === panel else { return }
        clearTextEditingHold()
        reconcileAfterTerminalEvent()
    }

    @objc private func frontmostApplicationChanged(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        invalidateComposerFocusRequest()
        clearTextEditingHold()
        reconcileAfterTerminalEvent(releaseMouseButton: true)
    }

    private func textInputActivity() {
        cancelPendingWork()
        if !captureTextEditingHoldFromResponder(matching: nil), !isAnimating {
            // List navigation/copy is transient engagement: restart the bounded
            // outside grace without manufacturing a persistent editing hold.
            rearmFromTrackedPointerState()
        }
    }

    @discardableResult
    private func captureTextEditingHoldFromResponder(matching target: NSView?) -> Bool {
        guard let editor = panel.firstResponder as? NSTextView, editor.isEditable else { return false }
        if let target {
            let matchesTextView = target === editor
            let matchesFieldEditor = (target as? NSTextField).map {
                panel.fieldEditor(false, for: $0) === editor
            } ?? false
            guard matchesTextView || matchesFieldEditor else { return false }
        }
        activeTextEditor = editor
        isTextEditing = true
        cancelPendingWork()
        return true
    }

    private func clearTextEditingHold() {
        activeTextEditor = nil
        isTextEditing = false
    }

    private func clearTransientEngagementForHiddenState() {
        invalidateComposerFocusRequest()
        focusComposerAfterReveal = false
        mouseButtonDown = false
        isMenuTracking = false
        clearTextEditingHold()
    }

    private func invalidateComposerFocusRequest() {
        composerFocusGeneration &+= 1
    }

    private func trace(_ message: @autoclosure () -> String) {
        guard panelTraceEnabled else { return }
        let line = "[CuePanelTrace] \(Date().timeIntervalSince1970) \(message())\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    /// Actual AppKit integration seam: drives the real retained-Sidecar panel
    /// through the reducer into a rail without waiting for wall-clock input.
    /// Production paths never call this method.
    func runIntegrationRetractionProbe() -> NSRect? {
        _ = process(.show(reason: .hover))
        pointerInside = false
        clearTextEditingHold()
        mouseButtonDown = false
        isMenuTracking = false
        let effects = process(.hoverExited)
        guard let token = effects.compactMap({ effect -> Int? in
            if case let .scheduleRetraction(token) = effect { return token }
            return nil
        }).first else { return nil }
        cancelPendingWork()
        guard let placement = PanelGeometryPolicy.railPlacement(for: expandedFrame, screens: screenGeometries) else { return nil }
        pendingRailPlacement = placement
        _ = process(.retractDeadline(token: token, edge: placement.edge))
        return placement.frame
    }

    func runIntegrationPointerEntered(timestamp: TimeInterval) {
        acceptTrackingEvent(.entered, timestamp: timestamp)
    }

    func runIntegrationRailClick() {
        handleExplicitMouseInteraction()
    }

    /// Seeds a prior interaction epoch so the public toggle path can prove
    /// that hidden presentation never leaks transient engagement into reveal.
    func runIntegrationSeedTransientEngagement() {
        mouseButtonDown = true
        isMenuTracking = true
        isTextEditing = true
    }

    var integrationPresentationState: PanelPresentationState { machine.state }
    var integrationPresentationGeneration: Int { machine.generation }
    var integrationLastRevealReason: PanelRevealReason { lastRevealReason }
    var integrationExpandedFrame: NSRect { expandedFrame }
    var integrationPanelFrame: NSRect { panel.frame }
    var integrationPanelMinSize: NSSize { panel.minSize }
    var integrationContentMinSize: NSSize { panel.contentMinSize }

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
