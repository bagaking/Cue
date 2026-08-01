import Foundation
import CoreGraphics

enum PanelEdge: String, Equatable, Sendable {
    case left
    case right
}

enum PanelRevealReason: Equatable, Sendable {
    case explicit
    case hover
    case pin

    var allowsFocus: Bool { self == .explicit }
    var usesTemporaryFloatingLevel: Bool { self == .hover }
}

enum PanelPresentationState: Equatable, Sendable {
    case hidden
    case expanded
    case retracted(PanelEdge)
}

enum PanelPresentationEffect: Equatable, Sendable {
    case cancelPending
    case presentExpanded(reason: PanelRevealReason)
    case presentRetracted
    case orderOut
    case scheduleHoverReveal(token: Int)
    case scheduleRetraction(token: Int)
}

enum PanelPresentationEvent: Equatable, Sendable {
    case show(reason: PanelRevealReason)
    case toggle
    case hide
    case hoverEntered
    case hoverExited
    case hoverRevealDeadline(token: Int)
    case retractDeadline(token: Int, edge: PanelEdge?)
    case setPinned(Bool)
    case repairRetractedEdge(PanelEdge)
}

/// Pure presentation reducer. Every delayed action carries the generation that
/// created it, so a reverse transition makes an older callback inert.
struct PanelPresentationMachine: Equatable, Sendable {
    private(set) var state: PanelPresentationState = .hidden
    private(set) var generation = 0
    private(set) var isPinned = false

    mutating func handle(_ event: PanelPresentationEvent) -> [PanelPresentationEffect] {
        switch event {
        case let .show(reason):
            invalidate()
            state = .expanded
            return [.cancelPending, .presentExpanded(reason: reason)]

        case .toggle:
            invalidate()
            if state == .expanded {
                state = .hidden
                return [.cancelPending, .orderOut]
            }
            state = .expanded
            return [.cancelPending, .presentExpanded(reason: .explicit)]

        case .hide:
            invalidate()
            state = .hidden
            return [.cancelPending, .orderOut]

        case .hoverEntered:
            invalidate()
            guard case .retracted = state else { return [.cancelPending] }
            return [.cancelPending, .scheduleHoverReveal(token: generation)]

        case .hoverExited:
            invalidate()
            guard state == .expanded, !isPinned else { return [.cancelPending] }
            return [.cancelPending, .scheduleRetraction(token: generation)]

        case let .hoverRevealDeadline(token):
            guard token == generation, case .retracted = state else { return [] }
            state = .expanded
            return [.presentExpanded(reason: .hover)]

        case let .retractDeadline(token, edge):
            guard token == generation, state == .expanded, !isPinned, let edge else { return [] }
            state = .retracted(edge)
            return [.presentRetracted]

        case let .setPinned(pinned):
            invalidate()
            isPinned = pinned
            if pinned, case .retracted = state {
                state = .expanded
                return [.cancelPending, .presentExpanded(reason: .pin)]
            }
            return [.cancelPending]

        case let .repairRetractedEdge(edge):
            invalidate()
            guard case .retracted = state else { return [.cancelPending] }
            state = .retracted(edge)
            return [.cancelPending]
        }
    }

    private mutating func invalidate() {
        generation &+= 1
    }
}

struct PanelScreenGeometry: Sendable {
    var id: String
    var frame: CGRect
    var visibleFrame: CGRect
}

struct PanelRailPlacement: Sendable {
    var edge: PanelEdge
    var frame: CGRect
    var screenID: String
    var isPhysicalOuterEdge: Bool
}

enum PanelTrackingEventKind: Sendable {
    case entered
    case exited
}

/// Accepts native tracking events only when they are newer than the most
/// recent programmatic frame move and are not contradicted by Quartz's
/// current global pointer position.
enum PanelTrackingPolicy {
    static func accepts(
        _ kind: PanelTrackingEventKind,
        eventTimestamp: TimeInterval,
        fence: TimeInterval,
        isAnimating: Bool,
        actualPointerInside: Bool?,
        actualPointerMovedSinceSettle: Bool?,
        requiresPhysicalMotionEvidence: Bool
    ) -> Bool {
        guard !isAnimating, eventTimestamp > fence else { return false }
        if requiresPhysicalMotionEvidence, actualPointerMovedSinceSettle != true { return false }
        switch (kind, actualPointerInside) {
        case (.entered, false), (.exited, true):
            return false
        default:
            return true
        }
    }

    static func shouldReplayRailEntry(
        transitionStartPointer: CGPoint?,
        settledPointer: CGPoint?,
        railFrame: CGRect
    ) -> Bool {
        guard let transitionStartPointer, let settledPointer,
              railFrame.contains(settledPointer) else { return false }
        return abs(settledPointer.x - transitionStartPointer.x) > 0.5 ||
            abs(settledPointer.y - transitionStartPointer.y) > 0.5
    }
}

enum PanelGeometryPolicy {
    static let minimumExpandedSize = CGSize(width: 352, height: 500)
    static let maximumExpandedSize = CGSize(width: 560, height: 900)
    static let railSize = CGSize(width: 22, height: 88)
    static let expandedMargin: CGFloat = 8
    static let railVerticalMargin: CGFloat = 6

    static func ownerScreenIndex(for frame: CGRect, screens: [PanelScreenGeometry]) -> Int? {
        guard !screens.isEmpty else { return nil }
        let overlaps = screens.enumerated().map { index, screen in
            (index, intersectionArea(frame, screen.frame))
        }
        if let winner = overlaps.max(by: { lhs, rhs in
            if lhs.1 == rhs.1 {
                return distanceSquared(frame.center, screens[lhs.0].frame.center) >
                    distanceSquared(frame.center, screens[rhs.0].frame.center)
            }
            return lhs.1 < rhs.1
        }), winner.1 > 0 {
            return winner.0
        }
        return screens.indices.min {
            distanceSquared(frame.center, screens[$0].visibleFrame.center) <
                distanceSquared(frame.center, screens[$1].visibleFrame.center)
        }
    }

    static func repairExpandedFrame(_ frame: CGRect, screens: [PanelScreenGeometry]) -> CGRect? {
        guard let ownerIndex = ownerScreenIndex(for: frame, screens: screens) else { return nil }
        let visible = screens[ownerIndex].visibleFrame
        guard visible.width >= minimumExpandedSize.width + expandedMargin * 2,
              visible.height >= minimumExpandedSize.height + expandedMargin * 2 else { return nil }

        var repaired = frame
        repaired.size.width = min(max(frame.width, minimumExpandedSize.width), min(maximumExpandedSize.width, visible.width - expandedMargin * 2))
        repaired.size.height = min(max(frame.height, minimumExpandedSize.height), min(maximumExpandedSize.height, visible.height - expandedMargin * 2))
        repaired.origin.x = min(max(frame.minX, visible.minX + expandedMargin), visible.maxX - repaired.width - expandedMargin)
        repaired.origin.y = min(max(frame.minY, visible.minY + expandedMargin), visible.maxY - repaired.height - expandedMargin)
        return repaired
    }

    static func railPlacement(
        for expandedFrame: CGRect,
        screens: [PanelScreenGeometry],
        railSize: CGSize = railSize
    ) -> PanelRailPlacement? {
        guard railSize.width >= 18, railSize.height >= 44,
              let ownerIndex = ownerScreenIndex(for: expandedFrame, screens: screens) else { return nil }
        let owner = screens[ownerIndex]
        let visible = owner.visibleFrame
        guard visible.width >= railSize.width, visible.height >= railSize.height + railVerticalMargin * 2 else { return nil }

        let y = min(
            max(expandedFrame.midY - railSize.height / 2, visible.minY + railVerticalMargin),
            visible.maxY - railSize.height - railVerticalMargin
        )
        let candidates: [PanelRailPlacement] = [
            placement(edge: .left, y: y, size: railSize, owner: owner, screens: screens),
            placement(edge: .right, y: y, size: railSize, owner: owner, screens: screens),
        ]
        return candidates.min { lhs, rhs in
            score(lhs, expandedFrame: expandedFrame, owner: owner) <
                score(rhs, expandedFrame: expandedFrame, owner: owner)
        }
    }

    /// A hover preview may temporarily bridge the expanded panel to its rail.
    /// The canonical expanded frame remains unchanged and is restored for
    /// explicit or pinned presentation.
    static func hoverExpandedFrame(
        canonicalExpandedFrame: CGRect,
        railPlacement: PanelRailPlacement
    ) -> CGRect {
        var frame = canonicalExpandedFrame
        switch railPlacement.edge {
        case .left:
            frame.origin.x += railPlacement.frame.minX - canonicalExpandedFrame.minX
        case .right:
            frame.origin.x += railPlacement.frame.maxX - canonicalExpandedFrame.maxX
        }
        return frame
    }

    private static func placement(
        edge: PanelEdge,
        y: CGFloat,
        size: CGSize,
        owner: PanelScreenGeometry,
        screens: [PanelScreenGeometry]
    ) -> PanelRailPlacement {
        let x = edge == .left ? owner.visibleFrame.minX : owner.visibleFrame.maxX - size.width
        let rail = CGRect(x: x, y: y, width: size.width, height: size.height)
        let outsideProbe = edge == .left
            ? CGRect(x: owner.frame.minX - 1, y: rail.minY, width: 1, height: rail.height)
            : CGRect(x: owner.frame.maxX, y: rail.minY, width: 1, height: rail.height)
        let isOuter = !screens.contains { screen in
            screen.id != owner.id && intersectionArea(outsideProbe, screen.frame) > 0
        }
        return PanelRailPlacement(edge: edge, frame: rail, screenID: owner.id, isPhysicalOuterEdge: isOuter)
    }

    private static func score(
        _ placement: PanelRailPlacement,
        expandedFrame: CGRect,
        owner: PanelScreenGeometry
    ) -> CGFloat {
        let inset = placement.edge == .left
            ? owner.visibleFrame.minX - owner.frame.minX
            : owner.frame.maxX - owner.visibleFrame.maxX
        let distance = placement.edge == .left
            ? abs(expandedFrame.minX - owner.visibleFrame.minX)
            : abs(owner.visibleFrame.maxX - expandedFrame.maxX)
        // A true exterior edge is the strongest signal; the visible-frame
        // inset then avoids Dock or Stage Manager territory when possible.
        return (placement.isPhysicalOuterEdge ? 0 : 100_000) + inset * 1_000 + distance
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let value = lhs.intersection(rhs)
        return value.isNull ? 0 : max(0, value.width) * max(0, value.height)
    }

    private static func distanceSquared(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }
}

/// Snapshot of interaction facts sampled by the AppKit owner at a retract
/// deadline. `isKeyWindow` is deliberately not an engagement hold: a
/// nonactivating NSPanel can remain key after the user has moved to another app.
struct PanelEngagementSnapshot: Equatable, Sendable {
    var panelPinned = false
    var pointerInside = false
    var isKeyWindow = false
    var isTextEditing = false
    var mouseButtonDown = false
    var isMenuTracking = false
    var isLiveResizing = false
    var hasAttachedSheet = false
    var hasModalWindow = false
}

enum PanelEngagementPolicy {
    static func allowsAutoRetraction(_ snapshot: PanelEngagementSnapshot) -> Bool {
        !snapshot.panelPinned &&
            !snapshot.pointerInside &&
            !snapshot.isTextEditing &&
            !snapshot.mouseButtonDown &&
            !snapshot.isMenuTracking &&
            !snapshot.isLiveResizing &&
            !snapshot.hasAttachedSheet &&
            !snapshot.hasModalWindow
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
