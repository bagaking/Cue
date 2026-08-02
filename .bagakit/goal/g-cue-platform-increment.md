---
schema: bagakit.loop-goal.v1
protocol_version: bagakit.goal.v.0.3
goal_id: g-cue-platform-increment
status: active
truth_surface: .bagakit/goal/g-cue-platform-increment.md
execution_owner:
  kind: bagakit-feature-tracker
  ref: .bagakit/feature-tracker/features/f-222j2ekp8
completion_evidence: []
---

# Goal: Cue Screenshot Attachments and Sync Portability

## Prime Directive
Deliver Cue screenshot attachments and a conflict-safe portability foundation because capture value depends on open, durable content rather than a closed local database.

## Protected Invariants
- Each .cue package remains the only mutable content truth; attachments, CLI and future clients share one storage contract.
- Privacy remains explicit-command, local-first and fail-closed; non-goals include OCR, passive capture, automatic upload and an account backend.

## Acceptance And Stop Rules
- Acceptance: market evidence and the .cue/.cue.md contract are reviewed, then screenshot storage, capture and transfer behavior pass their owner gates.
- Insufficient: a format proposal without crash/conflict safety, or screenshot UI without recoverable asset truth, does not count.
- Stop and ask when: a provider/account choice, private API, privacy weakening or destructive migration becomes necessary.
- Stop as complete when: Feature f-222j2ekp8 is closed with gate, commit, package and runtime evidence.

## Authority And Orchestration
- Feature Tracker f-222j2ekp8 owns live tasks and evidence; this Goal stays paused only while the urgent edge-obstruction hotfix is foreground.
- One integration writer owns mutations; independent agents diagnose or review read-only and user authority controls outcome or privacy expansion.

## Context References
- .bagakit/feature-tracker/features/f-222j2ekp8/proposal.md: explains product and architecture boundaries; read when resuming the platform increment.
