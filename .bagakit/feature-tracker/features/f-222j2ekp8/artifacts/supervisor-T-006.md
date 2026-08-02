# T-006 Supervisor Packet

## Execution contract

- owner: `f-222j2ekp8/T-006`
- integration writer: unassigned while architecture review is active
- mutation root: current tree on `main`
- protected baseline: Cue 0.2.0 schema-2 packages remain readable and are
  migrated only by a verified schema-3 write
- terminal condition: every T-006 acceptance criterion has deterministic gate
  evidence, one reviewable implementation commit is pushed, and Tracker records
  the gate and commit

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

## Preserved unrelated work

- `scripts/package_app.sh` is modified before T-006 execution and remains
  user-owned
- `scripts/reauthorize.sh` is untracked before T-006 execution and remains
  user-owned
- no T-006 worker may edit, stage, delete, or commit either path

## HANDOFF_READY

- HEAD/upstream: `ec62909`, `main == origin/main`
- Tracker: T-006 remains `in_progress`; no implementation commit exists
- integration writer: none; all schema-3 architecture agents are stopped
- active side effects: none; no build, test, package, deploy, or app process was
  started in this round
- implementation: not started
- passed evidence: Tracker validation and Goal fresh-executor check; prior
  0.2.0 baseline passed 92 Core and 63 AppKit checks before T-006 started
- not run: every T-006-specific codec, migration, concurrency, failpoint,
  package, and runtime gate

## Architecture handoff

- schema 3 manifest keeps schema/workspace identity/title and required feature
  declarations, never record membership
- membership is derived from `sections/`, `items/**/<id>.cue.md`, and
  `tombstones/`; symlinks, duplicate identities, and path/identity mismatch
  fail closed
- one Foundation-only record codec owns both internal item records and explicit
  external `.cue.md`; Cue metadata uses one namespaced flow value while non-Cue
  frontmatter, unknown Cue keys, and Markdown body bytes round-trip
- storage API should replace naked fingerprint/write calls with a loaded
  snapshot/revision and commit based on that snapshot
- commit builds and validates a same-volume sibling stage, coordinates a final
  live revision check, atomically replaces the package, and retains a valid
  prior package without remove-then-copy rollback
- tombstones bind the observed record revision/hash; divergent edit/delete
  preserves the record and tombstone as a typed conflict
- schema 2 opens without mutation; its first verified write stages schema 3;
  legacy aggregate Markdown remains a separate internal migration path

## Remaining design gates

- lock the honest downgrade behavior for schema-2 wall-clock tombstones that
  have no observed revision/hash; do not invent v3 evidence
- prove macOS directory `replaceItemAt` behavior under every pre/post-publication
  failpoint before treating it as the transaction commit point
- decide the smallest `CueCore` target extraction that gives app and future
  clients one Foundation-only writer without widening T-006 into CLI UI

## Next owner action

1. Re-read `AGENTS.md`, Goal, this packet, T-006, proposal, synthesis, and
   claims c004/c005/c007/c010.
2. Verify the preserved dirty paths still belong to the user.
3. Run a bounded architecture principle review over the three remaining gates.
4. Assign exactly one writable schema-3 implementation owner; keep transaction
   and migration reviewers read-only.
5. Implement and prove T-006; do not start T-007 attachments until Tracker has
   recorded T-006 gate, commit, and finish evidence.

## Forbidden retries

- do not layer attachments onto schema 2
- do not restore manifest membership or a second record writer
- do not use wall-clock last-write-wins for edit/delete
- do not repair publication by deleting live then copying backup
- do not touch or stage `scripts/package_app.sh` or `scripts/reauthorize.sh`
