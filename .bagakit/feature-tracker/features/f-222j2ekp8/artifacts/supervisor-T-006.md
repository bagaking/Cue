# T-006 Supervisor Packet

## Execution contract

- owner: `f-222j2ekp8/T-006`
- integration writer: `/root/t006_writer`; all other agents are read-only
- mutation root: current tree on `main`
- protected baseline: Cue 0.2.0 schema-2 packages remain readable and are
  migrated only by a verified schema-3 write
- terminal condition: every T-006 acceptance criterion has deterministic gate
  evidence, rollback-sized behavior-closed commits are reviewed and pushed,
  and Tracker records the gate, prepared commit, and task finish

## Protected-principle gate

- protected goal: one mutable `.cue` truth survives migration, concurrent
  writers, crash failpoints, rollback, direct Markdown edits, and unsupported
  newer schemas without silent loss
- project-native strategy: replace the current WorkspaceStore/package-codec
  contract at its owner boundary using Foundation coordination, a same-volume
  staged package, directory-derived membership, revision/hash tombstones, and
  one package/external-record codec
- failure boundary: manifest membership, document/fingerprint split snapshots,
  precondition TOCTOU, hybrid publication, remove-then-copy rollback, body or
  unknown-frontmatter loss, or a second writer implementation all fail the task
- proof plan: schema-2 migration, unknown-field/body round-trip, explicit
  `.cue.md` import/export, dual-writer single-winner, every publication
  failpoint old-or-new, revision-aware edit/delete conflicts, full regression,
  warnings-as-errors, and independent crash/codec review

## Protected paths

- `scripts/package_app.sh` and `scripts/reauthorize.sh` are committed baseline
  at `b3fa432`; the user's current T-006 authority still forbids editing,
  staging, deleting, or recommitting either path

## HANDOFF_READY

- HEAD/upstream at writer assignment: `b3fa432`, `main == origin/main`
- worktree at writer assignment: clean
- Tracker: T-006 remains `in_progress`; no implementation commit exists
- integration writer: `/root/t006_writer`; principle, transaction, migration,
  codec, and final reviewers remain read-only
- active side effects at recovery: one process from
  `dist/Cue.app/Contents/MacOS/Cue` was already alive as PID 43717; the writer
  did not start, package, relaunch, or reset permissions
- implementation: Slice A extraction is complete in the worktree and awaiting
  commit; schema behavior remains version 2
- passed evidence: Tracker validation and Goal fresh-executor check; prior
  0.2.0 baseline passed 92 Core and 63 AppKit checks before T-006 started;
  Researcher pass 002's standalone macOS process probe observed pre-publish
  live-old plus staged-new, post-publish live-new plus retained backup-old, and
  exactly one winner for two coordinated writers using the same expected
  generation; Slice A warnings-as-errors build and 91 Core plus 66 AppKit
  integration checks pass
- not run: every T-006-specific codec, migration, concurrency, failpoint,
  package, and runtime gate

## Architecture handoff

- schema 3 manifest keeps schema/workspace identity/title and required feature
  declarations, never record membership
- membership is derived from `sections/`, `items/**/<id>.cue.md`, and
  `tombstones/`; symlinks, duplicate identities, and path/identity mismatch
  fail closed
- one UI-framework-free shared record codec owns both internal item records and
  explicit external `.cue.md`; Cue metadata uses one namespaced flow value
  while non-Cue frontmatter, unknown Cue keys, and Markdown body bytes
  round-trip
- storage API should replace naked fingerprint/write calls with a loaded
  snapshot/revision and commit based on that snapshot
- commit builds and validates a same-volume sibling stage, coordinates a final
  live revision check, publishes through Foundation safe replacement, and
  retains a valid prior package without remove-then-copy rollback
- tombstones bind the observed record revision/hash; divergent edit/delete
  preserves the record and tombstone as a typed conflict
- schema 2 opens without mutation; its first verified write stages schema 3;
  legacy aggregate Markdown remains a separate internal migration path

## Locked design gates

- schema-2 wall-clock tombstones migrate as `legacyUnbound` audit evidence:
  the timestamp remains provenance only, never becomes an observed revision,
  never establishes dominance, and never suppresses a coexisting record. A
  record plus `legacyUnbound` tombstone preserves both and surfaces a typed
  legacy delete/edit conflict.
- one `WorkspaceSnapshot` owns the normalized document, exact package
  revision, raw lossless item envelopes, tombstones, typed conflicts, and
  read-only capability status. Mutation commits consume a loaded snapshot plus
  an intended draft; document and fingerprint are never separate authorities.
- `CueCore` is the smallest UI-framework-free shared target: domain persistence
  models, exact-byte SHA-256 revision support, shared record codec, schema-2
  reader/schema-3 writer, snapshot/transaction/store, and storage conflicts.
  It imports Foundation and the existing Apple CryptoKit SHA implementation;
  it contains no AppKit, SwiftUI, Combine, settings, panel, capture, cache,
  attachment, CLI, or mobile UI code.
- publication uses a hidden same-parent stage, synchronizes and fully validates
  it, then enters one `NSFileCoordinator` write accessor with `options: []`,
  rechecks the live exact-byte revision there, and calls
  `FileManager.replaceItemAt` with a named retained backup. The accessor URL
  and returned replacement URL are authoritative. A post-publication failure
  preserves live plus displaced packages and returns typed recovery; rollback
  never removes live and copies a backup back.
- proof promises complete old-or-new packages at every owned
  application/process failpoint, a retained prior package, and exactly one
  participating same-revision writer. Apple docs and the local process probe
  do not prove power-cut durability, arbitrary filesystem behavior,
  non-participating writer safety, dual-Mac convergence, or reliable sync.
- the selected writer remains Foundation-owned. Darwin `rename`/`renamex_np`
  documentation is counterevidence against overclaiming, not authority to add
  a second platform-specific publication implementation.

## Next owner action

1. The truth-alignment slice is pushed as `9bdca1e` on `origin/main`.
2. Review and commit the minimal UI-framework-free `CueCore` extraction under
   `Sources/CueCore/`; legacy aggregate Markdown and derived search cache stay
   under `Sources/Cue/`, and the executable plus checks consume the sole Core
   package writer.
3. Land the shared lossless record/schema codec, then the coordinated
   transaction, then snapshot-based AppModel recovery/Undo in separate
   rollback-sized behavior closures.
4. Keep transaction, migration/codec, privacy/runtime, and final adversarial
   reviewers read-only; correct root causes before each commit.
5. Do not start T-007 attachments until Tracker has recorded T-006 gate,
   prepared commit evidence, finish, and origin/main proof.

## Forbidden retries

- do not layer attachments onto schema 2
- do not restore manifest membership or a second record writer
- do not use wall-clock last-write-wins for edit/delete
- do not repair publication by deleting live then copying backup
- do not touch or stage `scripts/package_app.sh` or `scripts/reauthorize.sh`
