---
schema: bagakit.loop-goal.v1
protocol_version: bagakit.goal.v.0.3
goal_id: g-cue-edge-hotfix
status: active
truth_surface: .bagakit/goal/g-cue-edge-hotfix.md
execution_owner:
  kind: bagakit-feature-tracker
  ref: .bagakit/feature-tracker/features/f-224j2prfr
completion_evidence: []
---

# Goal: Cue Unobtrusive Edge Retraction

## Prime Directive
Make Cue yield screen space after disengagement by reliably collapsing every unpinned visible panel into a small reachable edge target, then ship and run the exact verified build.

## Protected Invariants
- FloatingPanelController remains the single presentation owner; no second window, global pointer polling, sticky timer workaround or new dependency.
- Drafts, active typing, mouse drag, resize, menus, focus safety, explicit reveal, expanded geometry and multi-display reachability remain protected; content storage is out of scope.

## Acceptance And Stop Rules
- Acceptance: the actual obstruction reproducer is fixed, deterministic owner and full checks pass, and the signed dist/Cue.app is restarted from the committed build.
- Insufficient: reducer-only green without real packaged behavior, or a restart without a causal fix and regression proof, does not count.
- Stop and ask when: the fix would require passive monitoring, a second panel, broader product semantics, data migration or destructive user-state changes.
- Stop as complete when: Feature f-224j2prfr is closed with implementation, runtime, push and Tracker evidence.

## Authority And Orchestration
- Feature Tracker f-224j2prfr owns live tasks, gates and evidence; one writable worker implements while the main agent supervises and independent reviewers remain read-only.
- The user alone may broaden outcome, protected behavior or irreversible state; the supervisor may reject weak proof and require root-cause repair.

## Context References
- .bagakit/feature-tracker/features/f-224j2prfr/proposal.md: explains the obstruction contract and scope; read before mutation or review.
- AGENTS.md: explains Cue product and proof invariants; read after compact or ownership transfer.
