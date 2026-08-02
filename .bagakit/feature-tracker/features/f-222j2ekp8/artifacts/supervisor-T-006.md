# T-006 Supervisor Packet

## Execution contract

- owner: `f-222j2ekp8/T-006`
- integration writer: `/root/t006_writer_recovery`; the bounded B2
  error-boundary writer handed the green tree back, and all other agents are
  read-only
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

- HEAD/upstream at recovery-writer assignment: `e07cb07`, `main == origin/main`
- worktree at recovery-writer assignment: B1 codec/tests and this supervisor
  packet were dirty, with an empty staged index
- Tracker: T-006 remains `in_progress`; Slice B1 is pushed as `ef8dc9a`, while
  T-006 gate, prepared-commit, and finish evidence are not yet recorded
- integration writer: `/root/t006_writer_recovery`; its bounded
  `/root/t006_writer_recovery/b2_collision_writer` child completed the B2
  error-boundary correction and handed ownership back; principle, transaction,
  migration, codec, and final reviewers remain read-only
- active side effects at recovery: one process from
  `dist/Cue.app/Contents/MacOS/Cue` was already alive as PID 43717; the writer
  did not start, package, relaunch, or reset permissions
- implementation: Slice A is pushed as `e07cb07`; Slice B1 is pushed as
  `ef8dc9a` and adds the public
  lossless `CueItemRecordCodec` without activating schema 3 in
  `WorkspaceStore`, so live package behavior remains schema 2
- passed evidence: Tracker validation and Goal fresh-executor check; prior
  0.2.0 baseline passed 92 Core and 63 AppKit checks before T-006 started;
  Researcher pass 002's standalone macOS process probe observed pre-publish
  live-old plus staged-new, post-publish live-new plus retained backup-old, and
  exactly one winner for two coordinated writers using the same expected
  generation; Slice B1 warnings-as-errors, 119 Core checks, 66 AppKit
  integration checks, Tracker validation, and independent adversarial codec
  review pass; current Slice B2 bytes pass warnings-as-errors; exactly one full
  `sh scripts/check.sh` run passes 257 Core checks and 66 AppKit integration
  checks after correcting a `/var` versus `/private/var` fixture-path alias and
  preserving real filesystem read errors outside decoder normalization; both
  independent final B2 code reviews and Feature Tracker validation pass; the
  final staged blob/message/allowlist review passed its code and message
  portions and blocked only on the stale owner-evidence wording corrected here
- Slice B2 is pushed as `de6dff5` on `origin/main`. Slice C now owns coordinated
  snapshot/CAS and staged publication; AppModel snapshot adoption, Undo and
  runtime qualification remain later closures.
- Slice C pre-mutation transaction and adversarial reviews pass with a locked
  S1-S5 process-failpoint matrix, authoritative accessor/returned-URL checks,
  exact source/target revision recovery evidence, and no power-loss,
  filesystem-general, non-participating-writer, or reliable-sync claim.

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
- Slice B2's unknown schema-2 metadata guarantee is scoped to item/source
  metadata carried into the shared schema-3 `cue` map. Unknown legacy
  manifest metadata blocks migration because the schema-3 manifest has exactly
  four keys; B2 does not invent a side channel or expand a section-metadata
  promise.
- The membership-free schema-3 manifest keeps the project-native keys
  `cue_schema`, `cue_workspace_id`, `title`, and `required_features` exactly;
  generic `schema`/`id` spellings are not a reviewed contract change.
- Slice B2 consumes a package URL supplied inside a future coordinated
  accessor, reads it exactly once into a raw inspection, and builds migration
  plans purely from that inspection. Coordination, CAS, staging, and
  publication remain Slice C owners.
- T-006 `tasks.json` source refs name the pre-extraction `Sources/Cue/` paths as
  immutable reviewed historical inputs while the task is active. The current
  owners are `Sources/CueCore/WorkspacePackageCodec.swift` and
  `Sources/CueCore/WorkspaceStore.swift`; only a reviewed later plan
  supersession may correct the canonical task refs.

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
2. The minimal UI-framework-free `CueCore` extraction is pushed as `e07cb07`;
   legacy aggregate Markdown and derived search cache remain app-side, and the
   executable plus checks consume the sole Core package writer.
3. Slice B1 is pushed as `ef8dc9a` and Slice B2 as `de6dff5`. Land Slice C's
   Foundation-only coordinated snapshot/transaction as one behavior closure,
   then adopt snapshots in AppModel recovery/Undo separately.
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

## UI-priority pause HANDOFF_READY

- pause owner: `/root/t006_writer_recovery` stopped at a command boundary on
  2026-08-03 after the supervisor reported a newer user-priority UI request;
  no App/UI mutation, new test admission, staging, commit, push, packaging, or
  runtime operation remains in flight
- Git identity: `HEAD == origin/main == de6dff527ca46fa200a4bbe4080fa51298423ac5`;
  the index is empty
- exact dirty ownership: this packet,
  `Sources/CueCore/Models.swift`, `Sources/CueCore/CuePackagePlan.swift`,
  `Sources/CueCore/WorkspaceStore.swift`, and
  `Checks/CueCoreChecks/main.swift`; `.bagakit/git-message-craft/` remains
  pre-existing user-owned untracked work
- protected paths: `scripts/package_app.sh` and `scripts/reauthorize.sh` have
  no diff and were not staged or executed
- latest bounded mutation: Checks now contain ordinary thrown S4/S5 recovery
  fixtures, a Checks-only `FileManager` override that performs the real
  replacement and then throws, and explicit read-only/unresolved-conflict
  pre-stage rejection fixtures; no production owner changed in this pause
  round
- last current-source compile evidence: `swift build` passed; a manual
  Foundation-only `CueCore` build against the installed macOS 15.4 SDK also
  passed under `/private/tmp/cue-t006-focused.9P8urz`
- test evidence boundary: the latest executed focused binary reported 312
  passed and 0 failed, but its timestamp predates the new fixtures and does
  **not** prove the current `Checks/CueCoreChecks/main.swift`; recompiling the
  check binary first hit the host's mismatched CLT compiler 6.3.0.123.5 versus
  default SDK 26.4 compiler 6.3.0.123.4, then the SDK-15.4 retry correctly
  rejected the existing SDK-26.4 `CueCore` module. No current-bytes Core total,
  warnings-as-errors, full `scripts/check.sh`, or final review is claimed.
- active process evidence: the only matching product/build/test process is the
  preserved packaged Cue PID 43717; no `swiftc`, `swift build`, Core check, or
  `scripts/check.sh` process remains
- exact resume action: compile `CueCoreChecks` against the already-built
  SDK-15.4 temporary `CueCore` module/library, run that focused binary outside
  the tool sandbox for file coordination, then run warnings-as-errors and
  independent current-byte review before admitting one final full gate
- forbidden resume shortcuts: do not reuse the stale 312/0 binary as current
  evidence, do not broaden into AppModel, attachments, UI, a second writer or
  codec, and do not stage/commit/push until the supervisor explicitly resumes
  this owner
