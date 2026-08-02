# Feature Proposal: f-226j2d2fx

## Why
- The retracted 22×88 rail currently reads as a wide outlined pill with no Cue identity and no clear physical-edge attachment.
- Note bodies already decode inline Markdown links, but link activation must be intentional: ordinary clicks belong to card selection/editing, while Command+click may open a safe web URL.

## Goal
- Make Cue rest as a quiet branded edge-attached tab and open note-body web links only through explicit Command+click, without changing panel reachability or ordinary card behavior.

## Principle Layer
- What: correct the retained rail's visual tongue/shadow and add one modifier-and-scheme policy around the existing inline Markdown note renderer.
- Why: Cue should yield the user's workspace and never turn displayed content into an accidental navigation surface.
- Intended generalization: the existing `.retracted(edge)` state remains the only edge owner, and the existing inline `AttributedString` remains the only note-body link decoder.
- Failure boundary: no rail geometry/state/timing change, second window/monitor/timer, new asset/palette, second Markdown/link renderer, detector/overlay/global monitor, unsafe URL scheme, ordinary-click navigation, or duplicated accessibility action.
- Behavior examples:
  - Count zero still shows the canonical Cue icon on a narrow left/light tab; count two remains secondary on a right/dark tab.
  - Hover/click reveal, focus, Pin, multi-display and Reduce Motion remain unchanged; only the settled retracted panel loses its shadow.
  - Command+click opens bare, angle-bracketed or labeled `http`/`https` links already recognized by inline Markdown.
  - Ordinary click, Command+click on non-web schemes, and malformed URLs do not navigate; ordinary click keeps card selection/edit semantics and Command+click does not also select/edit.
- Evidence refs:
  - `Resources/AppIcon.icns`
  - `Sources/Cue/PanelRootView.swift`
  - `Sources/Cue/FloatingPanelController.swift`
  - `Sources/Cue/WorkItemCard.swift`
  - `Sources/Cue/PreviewRenderer.swift`
  - `Sources/Cue/IntegrationCheckRunner.swift`

## Design And Product Packet
- Edge surface: keep one full 22×88 Button/window hit frame. Draw one 18×88 tongue aligned by physical left/right coordinates; the screen-facing side is flat, only the two inward corners use approximately 8-point continuous curves, and the inward 4 points remain transparent but hit-testable.
- Hierarchy: remove chevron and full outline. Show `NSApplication.applicationIconImage` as a non-template 15-point primary mark at every count; show a 13–14 point accent count as secondary feedback. Decorative children are accessibility-hidden and the existing Reveal Cue Button remains the sole accessible element.
- Material: apply popover material and the opaque/Reduce Transparency fallback only inside the tongue before placing it in the hit frame. Stable retracted `NSPanel.hasShadow` is false; initialization, transition and expanded states remain true.
- Edge evidence: render the actual `PanelRootView` inside screen context for left/light/count-zero, right/dark/count-two and opaque fallback. The preview-only unbundled process loads the existing `Resources/AppIcon.icns` fail-closed; production continues through the application icon API.
- Link surface: reuse `AttributedString(markdown:options:)` with `.inlineOnlyPreservingWhitespace`. Override `openURL` only around note body text and permit `NSWorkspace` opening only when Command is current and the URL scheme lowercases to `http` or `https`.
- Interaction: discard ordinary SwiftUI link activation so its enclosing card gesture retains selection/edit semantics. Guard existing card single/double gestures when Command is held so Command+click navigation cannot also select or edit. Reject `file`, custom and `javascript` schemes fail-closed.
- Accessibility: preserve the existing card VoiceOver surface and Reveal Cue button. Do not add duplicate link actions or accessible icon/count descendants.

## Scope
- In scope: `PanelRootView`, stable panel shadow, edge-context previews and panel checks; `WorkItemCard` modifier/scheme policy and gesture guards; deterministic integration checks and replacement Feature verification.
- Out of scope: `PanelPresentation`, AppModel, CueCore/storage/attachments, Package.swift, scripts, new URL parsing/detection, packaging or restarting the live app before supervisor approval.

## Acceptance Criteria
- The 18×88 visible tongue is correctly attached inside the unchanged 22×88 physical hit frame, with canonical brand, secondary count, no chevron/full outline and no settled retracted shadow.
- One Reveal Cue Button retains its current label/value/hint and all existing panel state, geometry, timing, focus, Pin, multi-display and Reduce Motion behavior.
- Required edge-context PNGs visibly prove the physical boundary, single contour, brand and transparent inward hit remainder.
- Bare, angle-bracketed and labeled inline Markdown web links open only on Command+click; `http` and `https` scheme matching is case-insensitive after normalization.
- Ordinary clicks retain selection/edit behavior; Command+click does not also invoke card gestures; missing modifiers and `file`/custom/`javascript` schemes never open.
- Independent design/runtime/security reviews have no blocking findings; warnings-as-errors, targeted checks and the full deterministic suite are classified honestly and pass for changed behavior.

## Transfer Checks
- Removing this feature leaves one panel owner and one inline Markdown renderer, not parallel state or parsing paths.
- Static PNGs plus the actual retained NSPanel path prove visual and runtime ownership; deterministic policy checks prove URL intent without launching an external app.
- Tracker gates and exact commits advance main/origin without staging paused T-006 dirty work or protected scripts.

## Impact
- Code paths: `PanelRootView`, `FloatingPanelController`, `PreviewRenderer`, `IntegrationCheckRunner`, `WorkItemCard`, and replacement verification only.
- Tests: actual panel shadow/frame/reveal checks; policy cases for modifier and scheme; edge-context renders with independent image inspection; warnings-as-errors and full suite.
- Rollout notes: implement directly in current main tree, preserve the paused platform increment, and defer packaging/runtime replacement to the supervisor delivery gate.
