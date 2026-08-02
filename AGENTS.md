# Cue — Agent Contract

## Fresh-executor recovery

Do this before planning, editing, testing, packaging, or trusting chat context:

1. Run `git status --short --branch` and `git log -5 --oneline --decorate`.
   Preserve every pre-existing change; never reset, clean, stash, or broadly
   stage work to simplify the task.
2. Read `.bagakit/goal/current.md`, then resolve `foreground_goal` through
   `.bagakit/goal/state.yaml`.
3. Read that Goal Kernel and its `execution_owner`. For a Feature Tracker
   owner, read `owner-receipt.json`, `state.json`, and `tasks.json`; task state
   and next action live there, not in the Goal prose.
   `lifecycle_status: ready` with no `current_item_id` means no task is running;
   the first `todo` is only a candidate until Tracker starts it.
4. Follow the current task's `source_refs`. When no task is running, use the
   Feature-level `source_refs` and the first `todo` candidate's refs for
   orientation only; they do not authorize or mark that task as started.
   Research starts at `.bagakit/researcher/index.md`; use the linked synthesis
   and claims before source cards. Research evidence explains decisions but
   does not prove a capability has shipped.
5. Read `docs/ARCHITECTURE.md` for stable code ownership and the explicit
   current-versus-planned boundary. Read `docs/PRODUCT.md` for shipped behavior
   and `docs/EXPERIMENTS.md` for product-level proof.
6. Reconcile all prose against the current Git diff, source, tests, packaged
   executable, and running process. When they disagree, do not guess: update
   the owning truth surface or report the mismatch.

Truth routing is deliberate:

| Question | Source of truth |
|---|---|
| Why Cue exists and what it must not become | this file + `docs/PRODUCT.md` |
| What work is active and what happens next | foreground Goal's execution owner |
| Why a product or architecture decision was made | Researcher synthesis, claims, then source cards |
| What the implementation currently does | source + deterministic checks |
| What exact build is delivered | Git HEAD + packaged executable hash + live process |

Do not turn README roadmap language, a research recommendation, a todo task, or
an old chat transcript into a shipped-capability claim.

## Product principle

Cue captures an explicit selected fragment or unsent prompt with minimal interruption, keeps it in one bounded local work queue, and makes reuse plus completion deliberate and recoverable.

## Hard boundaries

- Native macOS 14+ only; SwiftUI/AppKit and Apple frameworks are the project-native route.
- No account, cloud content sync, telemetry, passive clipboard history, passive screen capture, or arbitrary-app Send injection.
- Accessibility access is used only after an explicit capture command. Typed capture must remain useful without it.
- Each `.cue` package is the content source of truth: `manifest.yaml`, one readable Markdown file per WorkItem, section records, tombstones, and content-addressed assets. Settings and rebuildable search caches may store paths or derived data, never a parallel item database.
- Never silently overwrite an externally edited workspace. Never silently fall back to clipboard content when selected-text capture fails.
- Secure fields and denylisted apps persist zero captured content.
- Copying does not complete by default. All destructive-looking lifecycle actions must be recoverable through Undo or Archive restore.

## Build and proof

```bash
swift build
sh scripts/check.sh
sh scripts/package_app.sh
open dist/Cue.app
```

Behavior tests should cover per-item Markdown round trips, package structure, tombstone deletion, rebuildable indexes, atomic writes, external-edit conflicts, backup retention, duplicate suppression, merge, completion, archive/restore, responsive minimum-size renders, and undo snapshots.

The command list is not completion by itself. A release handoff must identify
the exact commit, test totals, signed packaged executable hash, and whether one
and only one process from that package is alive.
