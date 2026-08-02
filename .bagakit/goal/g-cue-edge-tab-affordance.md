---
schema: bagakit.loop-goal.v1
protocol_version: bagakit.goal.v.0.3
goal_id: g-cue-edge-tab-affordance
status: active
truth_surface: .bagakit/goal/g-cue-edge-tab-affordance.md
execution_owner:
  kind: bagakit-feature-tracker
  ref: .bagakit/feature-tracker/features/f-225j2syhf
completion_evidence: []
---

# Goal: Cue Edge Tab Affordance

## Prime Directive
Deliver a quiet branded edge tab that remains reachable without increasing obstruction or changing the retained panel lifecycle.

## Protected Invariants
- The existing CuePanel remains the only panel, frame and presentation owner; its 22×88 hit geometry, state machine, timings and multi-display behavior do not change.
- The canonical Cue app icon remains visible even at count zero; queue count is secondary, and the edge-attached shape—not a chevron, outline or window shadow—communicates direction.
- Paused schema-3 work and its dirty paths remain untouched and resumable; no packaging or live-process replacement occurs before an explicit delivery gate.

## Acceptance And Stop Rules
- Acceptance: left/light/count-zero, right/dark/count-two and opaque fallback renders prove a narrow flat-outer rounded-inward tongue in screen-edge context, while actual NSPanel checks prove shadow and interaction contracts.
- Insufficient: a tight-cropped SwiftUI snapshot, private shape test, build-only result, or visual change that alters panel geometry, state, timing, focus, accessibility or expanded UI does not count.
- Stop and ask when: delivery would require replacing the live process around preserved dirty root work, weakening accessibility, changing product behavior, or touching protected storage/script paths.
- Stop as complete when: Feature f-225j2syhf is closed with independent review, deterministic gates, exact commits and origin/main evidence; packaging/runtime evidence remains separately gated.

## Authority And Orchestration
- Feature Tracker f-225j2syhf is the sole execution owner; one writer mutates only its assigned worktree and independent reviewers remain read-only.
- Use project-native SwiftUI/AppKit and canonical assets; choose the smallest owner-native correction and prove public behavior before integration.

## Context References
- .bagakit/feature-tracker/features/f-225j2syhf/proposal.md: design packet, scope and acceptance; read before implementation or review
