# Feature Proposal: f-225j2syhf

## Why
- The shipped 22×88 retracted rail reads as a wide outlined pill with a generic chevron and count badge. It obscures the Cue identity and looks like a detached control instead of a tab emerging from the selected physical screen edge.
- The retained `CuePanel` already owns the correct hit target, reveal lifecycle and multi-display placement. This feature corrects only its visual affordance and retracted shadow contract.

## Goal
- Make the retained Cue edge rail a quiet, branded and reachable edge tab without changing its hit geometry, interaction state machine or expanded panel.

## Principle Layer
- What: render one 16–18 point visible tongue inside the existing 22×88 retracted panel, flush to the selected screen edge, with Cue's canonical application icon and a secondary queue count.
- Why: Cue should remain discoverable while yielding the user's working surface; a branded edge attachment communicates both identity and origin with less visual weight than a floating pill.
- Intended generalization: future edge polish may consume the same `.retracted(edge)` state and full-frame button, but must not introduce another window, state owner or persisted rail geometry.
- Failure boundary: no rail-size change, second window, monitor, timer, polling, new asset/palette, duplicated accessibility child, state-machine/timing change, compensating outline, or expanded-panel redesign.
- Behavior examples:
  - Count zero still shows the Cue app icon on a left/light edge tab.
  - Count two shows the same brand first and the existing accent second on a right/dark edge tab.
  - Hover keeps the current reveal deadline; click explicitly reveals and focuses; Reduce Motion keeps the current state semantics.
  - The retracted panel has no AppKit shadow; expanded and transitional presentation keeps the existing shadow.
- Evidence refs:
  - `Resources/AppIcon.icns`
  - `Sources/Cue/PanelRootView.swift`
  - `Sources/Cue/FloatingPanelController.swift`
  - `Sources/Cue/PanelPresentation.swift`
  - `Sources/Cue/PreviewRenderer.swift`
  - `.bagakit/feature-tracker/features-archived/f-223j2ezq3/artifacts/closeout-preserved-root/proposal.md`

## Design Packet
- Surface and audience: a retained native macOS sidecar tab for people actively working in another app; optimize for low obstruction, instant recognition and reliable reachability.
- Product model: the user disengages from expanded Cue, sees an idle edge tab, then either hovers for the existing preview or clicks for explicit reveal/focus. Queue count is feedback, not the primary object; completion is the unchanged expanded panel.
- Visual tonality: neutral native material, compact density, one Cue icon, restrained mint count accent, zero decorative outline, and one edge-attached contour. Reuse the app icon through the application icon API rather than adding an asset.
- Geometry: preserve the 22×88 panel/button/hit frame. Place a 16–18 point visible tongue flush to the physical edge; its edge-facing side is flat with zero radius and only its inward side receives approximately 8-point continuous corners. The transparent remainder extends inward for hit continuity.
- Hierarchy and semantics: Cue identity remains visible at every count; count is secondary; chevron is removed because the attached shape carries direction. One Button continues to own the full hit frame and the existing VoiceOver label, value and hint; rendered children add no accessibility elements.
- Material and contrast: preserve the popover material and the current opaque/Reduce Transparency fallback. Remove the full `strokeBorder`; do not add a second mask or compensating outline. Retracted `NSPanel.hasShadow` is false and expanded/transitional shadow remains true.
- Required states: idle tab, existing hover deadline/reveal, explicit click reveal/focus, unchanged expanded UI, unchanged Reduce Motion behavior, and opaque fallback.
- Review risks: a tight crop can hide edge attachment; icon downsampling can lose its card motif; a shadow or symmetric clipping can recreate the detached-pill defect; a badge can overwhelm the brand.

## Scope
- In scope: retracted SwiftUI contour/content, canonical app-icon reuse, retracted-versus-expanded panel shadow, edge-context preview fixtures, and narrow public integration assertions.
- Out of scope: panel geometry/state/timing changes, `PanelPresentation` changes unless proof forces one, content/storage/attachments, new settings, packaging or restarting the currently running app before the delivery gate.

## Acceptance Criteria
- The visible tongue is 16–18 points wide inside the unchanged 22×88 hit frame, flush to the chosen physical edge, flat on the edge-facing side and rounded only inward.
- The chevron and full outline are absent; the canonical Cue app icon is visible for count zero and count states use the existing accent only as secondary feedback.
- One full-frame Button retains current hover/click/focus behavior and existing VoiceOver label/value/hint without accessible child duplication.
- Retracted `CuePanel` shadow is off; expanded and transitional shadow is on; panel size, frame persistence, multi-display placement, reveal/retract timing and Reduce Motion semantics do not drift.
- Static evidence shows at least left/light/count-zero and right/dark/count-two tabs in physical edge context, plus opaque fallback coverage, with one contour and transparent inward hit remainder visible.

## Transfer Checks
- `swift build -Xswiftc -warnings-as-errors` and `sh scripts/check.sh` pass with retained geometry/state coverage and explicit panel-shadow assertions.
- An independent design/accessibility review inspects exact rendered PNGs; an independent AppKit/runtime review inspects owner boundaries and the final diff.
- Tracker gates bind the semantic acceptance and proof; exact commits advance `origin/main` without staging the paused T-006 dirty work or protected scripts.

## Impact
- Code paths: `PanelRootView`, `FloatingPanelController`, `PreviewRenderer`, and `IntegrationCheckRunner` only unless independent review proves a narrower owner-native exception.
- Tests: required static edge-context renders, actual retained-`NSPanel` shadow/interaction checks, warnings-as-errors, full deterministic suite, and independent final visual review.
- Rollout notes: land planning truth first, implement in the assigned Feature worktree, then integrate without packaging or restarting until the supervisor approves a runtime replacement strategy around the preserved root dirty tree.
