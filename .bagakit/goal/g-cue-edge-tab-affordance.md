---
schema: bagakit.loop-goal.v1
protocol_version: bagakit.goal.v.0.3
goal_id: g-cue-edge-tab-affordance
status: active
truth_surface: .bagakit/goal/g-cue-edge-tab-affordance.md
execution_owner:
  kind: bagakit-feature-tracker
  ref: .bagakit/feature-tracker/features/f-226j2d2fx
completion_evidence: []
---

# Goal: Cue Edge Tab and Intentional Links

## Prime Directive
Deliver a quiet branded edge tab and intentional note-body web navigation without increasing obstruction, accidental activation or interaction-owner complexity.

## Protected Invariants
- The existing CuePanel remains the only panel, frame and presentation owner; its 22×88 hit geometry, state machine, timings and multi-display behavior do not change.
- The canonical Cue app icon remains visible even at count zero; queue count is secondary, and the edge-attached shape—not a chevron, outline or settled window shadow—communicates direction.
- The existing inline Markdown AttributedString remains the only note-body link decoder; only explicit Command+click may open normalized http/https URLs, while ordinary clicks remain card interactions.
- Paused schema-3 work and its dirty paths remain untouched and resumable; no packaging or live-process replacement occurs before an explicit delivery gate.

## Acceptance And Stop Rules
- Acceptance: edge-context renders and actual NSPanel checks prove the branded physical-edge tab, while deterministic policy and card-path checks prove safe Command-click web links without ordinary-click or accessibility regressions.
- Insufficient: a tight-cropped render, private helper-only test, second parser/overlay, build-only result, or change to panel geometry/state/timing, card selection/edit semantics, accessibility ownership or unsupported URL schemes does not count.
- Stop and ask when: delivery would require replacing the live process around preserved dirty root work, weakening accessibility or URL safety, changing product behavior beyond the reviewed packet, or touching protected storage/script paths.
- Stop as complete when: replacement Feature f-226j2d2fx is closed with independent review, deterministic gates, exact commits and origin/main evidence; packaging/runtime evidence remains separately gated.

## Authority And Orchestration
- Feature Tracker f-226j2d2fx is the sole execution owner; one writer mutates current main and independent reviewers remain read-only.
- Use project-native SwiftUI/AppKit, canonical assets and the existing inline Markdown renderer; choose the smallest owner-native correction and prove public behavior before delivery.

## Context References
- .bagakit/feature-tracker/features/f-226j2d2fx/proposal.md: combined design/product packet, safety boundary and acceptance; read before implementation or review
