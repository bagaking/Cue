# Feature Proposal: f-224j2prfr

## Why
- Cue already owns an edge-retraction state machine, but the currently packaged instance can remain fully expanded after the user has disengaged. A 399×592 always-on-top surface obscures the work Cue is meant to support.
- This is a delivery failure at the public behavior boundary, not a request for a second window system. The existing `FloatingPanelController` must remain the sole visibility, frame, focus and transition owner.

## Goal
- Ensure every visible unpinned Cue instance reliably yields screen space after the user disengages, collapsing into a small reachable edge target without losing drafts, focus safety, drag/resize safety, multi-display reachability, or explicit reveal behavior; verify the packaged runtime, commit through Tracker, restart, and push the exact build.

## Principle Layer
- What: an unpinned visible Cue must leave the user's visual field after a bounded disengagement and settle into one small, reachable edge target; hover or an explicit command must restore it.
- Why: Cue lowers context-switching cost only if its idle visual tax approaches zero.
- Intended generalization: one owner-owned engagement contract should handle startup, explicit reveal, text editing, app switching, pin changes, drag/resize and future edge affordance polish.
- Failure boundary: no second panel, global pointer polling, sticky timeout workaround, mid-typing collapse, drag/resize interruption, lost draft/focus state, inaccessible rail, saved retracted geometry or content/storage changes.
- Behavior examples:
  - Launching or explicitly revealing an unpinned Cue while the pointer is outside arms one bounded retraction without requiring the pointer to enter and leave first.
  - Typing, menus, mouse-down/drag and live resize suspend retraction only while that engagement is live; ending it reliably rearms from current pointer truth.
  - Moving away from an idle panel yields a compact edge target; hover reveals without stealing focus, while click or shortcut explicitly reveals and may focus.
  - Panel Pin on remains the only persistent hold. Turning it off does not leave an orphaned hold and a later disengagement retracts normally.
- Evidence refs:
  - `AGENTS.md`
  - `Sources/Cue/FloatingPanelController.swift`
  - `Sources/Cue/PanelPresentation.swift`
  - `Sources/Cue/IntegrationCheckRunner.swift`
  - `docs/EXPERIMENTS.md`

## Scope
- In scope:
  - reproduce the current packaged behavior and identify the stale engagement or rearm path;
  - repair the existing single-owner state machine/controller contract;
  - deterministic checks for the reproducer plus the actual AppKit panel seam;
  - signed Release packaging, exact-runtime restart, origin push and a repeatable hands-on probe.
- Out of scope:
  - screenshot attachments, sync transport, `.cue.md`, storage schema or CLI work;
  - redesigning the full sidecar, recent-item edge preview, notification animation or green count dot;
  - passive/global cursor logging, a second hover window or new dependencies.

## Acceptance Criteria
- An unpinned Cue retracts from every idle expanded entry path without requiring a synthetic hover cycle and without staying expanded because a stale editing/focus/animation fact survived disengagement.
- Active typing, mouse-down/drag, menu, sheet, modal and live resize never collapse mid-interaction; their terminal events rearm exactly once from current pointer truth.
- The compact edge target stays reachable on physical outer edges, hover reveal remains focus-safe, explicit reveal remains deterministic, and user-selected expanded size/position survives.
- The exact regression has a deterministic owner-contract check, `sh scripts/check.sh` passes, and the packaged `dist/Cue.app` is signed, restarted and observed running from the committed build.

## Transfer Checks
- Removing this hotfix would re-expose one named public behavior regression; it does not create another presentation owner or a general idle subsystem.
- The fix remains compatible with the existing edge-preview/count direction because it changes engagement truth, not content truth or rail ownership.

## Impact
- Code paths: primarily `FloatingPanelController` and its pure policy/reducer; touch UI only if the reproducer proves the affordance itself is misleading.
- Tests: focused reducer/policy regression, AppKit integration seam, full `scripts/check.sh`, packaged real-window probe.
- Rollout notes: preserve `0ac58e6` as rollback; land one behavior commit, then one runtime-evidence/closeout commit, push and keep the exact `dist/Cue.app` process running.
