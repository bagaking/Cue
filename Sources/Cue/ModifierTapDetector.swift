import Foundation

/// Adapted from Pewter's MIT-licensed pure modifier-tap state machine.
/// Two complete, clean press-release cycles within the time window trigger.
struct ModifierTapDetector: Sendable {
    enum ShiftSide: Sendable {
        case left
        case right
    }

    enum ModifierEvent: Sendable {
        case targetAlone(side: ShiftSide)
        case none
        case other(targetHeld: Bool)
    }

    private let window: TimeInterval
    private var targetIsDown = false
    private var tapInProgress = false
    private var currentTapSide: ShiftSide?
    private var previousTapEndedAt: TimeInterval?
    private var previousTapSide: ShiftSide?

    init(window: TimeInterval = 0.35) {
        self.window = window
    }

    mutating func handleGestureBreak() {
        reset()
    }

    mutating func handleModifiers(_ event: ModifierEvent, timestamp: TimeInterval) -> Bool {
        switch event {
        case let .targetAlone(side):
            if !targetIsDown {
                targetIsDown = true
                tapInProgress = true
                currentTapSide = side
            } else if currentTapSide != side {
                tapInProgress = false
            }
            return false
        case .none:
            guard targetIsDown else { return false }
            targetIsDown = false
            let clean = tapInProgress
            let side = currentTapSide
            tapInProgress = false
            currentTapSide = nil
            guard clean, let side else { return false }
            if let previousTapEndedAt,
               previousTapSide == side,
               timestamp - previousTapEndedAt <= window {
                self.previousTapEndedAt = nil
                previousTapSide = nil
                return true
            }
            previousTapEndedAt = timestamp
            previousTapSide = side
            return false
        case let .other(targetHeld):
            reset()
            targetIsDown = targetHeld
            return false
        }
    }

    private mutating func reset() {
        targetIsDown = false
        tapInProgress = false
        currentTapSide = nil
        previousTapEndedAt = nil
        previousTapSide = nil
    }
}
