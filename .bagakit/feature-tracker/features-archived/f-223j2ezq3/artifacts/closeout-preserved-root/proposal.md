# Feature Proposal: f-223j2ezq3

## Why
- Cue's compact floating panel is useful while working with captured context, but an always-expanded 352–560 point window obscures the very app the user is trying to work in.
- Closing or globally hiding the panel removes obstruction at the cost of discoverability. A narrow edge rail gives Cue an ambient resting state that stays recoverable without becoming a second menu-bar-only interaction.
- The current panel already has one AppKit owner for visibility, animation, frame repair and window level. Edge behavior belongs in that owner rather than in a second overlay window or SwiftUI workaround.

## Goal
- Make Cue visually disappear when idle without becoming hard to recover: add a distinct panel Pin, edge retract, hover reveal, bounded delay and multi-display-safe geometry; then package, restart, commit and push the stable build.

## Principle Layer
- What: an unpinned Cue panel settles against an eligible left or right screen edge and exposes a small hover target; hovering or explicitly showing Cue restores its usable frame.
- Why: Cue should lower the friction of the next useful context without taxing the user's visual field between interactions.
- Intended generalization: one window-owner state machine can later drive an edge preview or pending-count signal without changing content storage, item lifecycle or window-level semantics.
- Failure boundary: no second panel/window, global mouse polling, inaccessible fully off-screen state, oscillating enter/exit animation, hard-coded primary-screen geometry, loss of the user's expanded size/position, or conflation of Panel Pin with item Pin or Always on Top.
- Behavior examples:
  - With Panel Pin off, moving the pointer away from an idle expanded panel arms one bounded retract delay; Cue then leaves a visible edge rail on the same display.
  - Hovering the rail reveals the full panel immediately; leaving the revealed panel starts a longer collapse delay so diagonal pointer movement and ordinary toolbar use do not jitter.
  - Clicking Panel Pin keeps the panel expanded across hover exits and restarts; Always on Top changes only `NSWindow.Level`; item Pin changes only work-item ordering/lifecycle.
  - Menu-bar command, global panel shortcut, composer shortcut and error-driven `show()` always reveal a retracted panel before focusing content.
  - Moving or resizing the window cancels pending motion, saves only the expanded frame and re-evaluates a true external edge on the display where the user left it; a seam shared with another display is not retractable.
- Evidence refs:
  - `AGENTS.md`
  - `Sources/Cue/FloatingPanelController.swift`
  - `Sources/Cue/CueMain.swift`
  - `Sources/Cue/SidecarView.swift`

## Scope
- In scope:
  - a persistent, top-chrome Panel Pin control with distinct accessibility copy;
  - controller-owned expanded, armed and retracted behavior with generation-safe animation;
  - left/right external-edge selection, safe delay, hover reveal, gap-free hysteresis and Reduce Motion behavior;
  - frame repair for display disconnects and visible-frame changes, including side Dock/menu-bar/Stage Manager insets;
  - deterministic geometry/state tests, release renders where meaningful and a real multi-display/full-screen probe;
  - signed Release packaging, restart, commit and push immediately after the slice is stable.
- Out of scope:
  - screenshot capture, OCR, sync transport and `.cue.md` compatibility work;
  - passive cursor logging, system-wide mouse tracking or a second always-on overlay window;
  - full recent-item edge preview, notification history, or a new preferences pane;
  - changing item Pin, archive, completion, content package or Always on Top semantics.

## Acceptance Criteria
- Panel Pin is visible in the top chrome, defaults to off for the obstruction-reducing behavior, persists through restart and has an unambiguous VoiceOver label/help string.
- An unpinned panel never becomes wholly inaccessible: the edge rail remains on an eligible physical edge and explicit show/toggle/composer actions always reveal it.
- Hover reveal is prompt; retract waits long enough to avoid accidental collapse; stale timers and animations cannot win after a newer interaction.
- The controller retains one canonical expanded frame, saves no programmatic/retracted frame even with Reduce Motion enabled, and preserves user-selected dimensions within the existing 352×500 to 560×900 bounds.
- Edge choice follows the panel's current screen, rejects seams shared with another display, avoids sides occupied by system UI when another external horizontal edge is eligible, and repairs safely after screen-parameter changes.
- The visible edge target and expanded hover-safe region have no cursor gap; leaving either state cannot create reveal/retract oscillation.
- Panel Pin, item Pin and Always on Top can be changed independently and automated checks prove the separate owner contracts.
- Full checks, Release package/signing and documented manual runtime probes pass before `origin/main` advances and the running Cue process is restarted from the packaged app.

## Transfer Checks
- Edge geometry and transition decisions are testable without launching a second GUI process.
- Removing the visual rail leaves one reusable panel presentation owner rather than AppKit/SwiftUI duplicate truth.
- Future edge preview/count polish can consume the same retracted state without changing the workspace package or item model.

## Impact
- Code paths: `FloatingPanelController`, top chrome in `SidecarView`, `AppSettings` persistence, app wiring and narrow state/geometry helpers owned by the panel layer.
- Tests: deterministic state/geometry scenarios in the core or integration runner, full `scripts/check.sh`, Release preview/build/signing, and hands-on secondary-display/full-screen hover probes.
- Rollout notes: preserve Cue 0.2.0 as the rollback boundary; first commit Tracker planning truth, then land one closed behavior commit and immediately repackage/restart before resuming the screenshot feature.
