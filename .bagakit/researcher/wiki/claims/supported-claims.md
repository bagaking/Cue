# Supported Claims

Status: research-local semantic index.

Claims listed here are pointers into topic claim ledgers.

## Claims
- `.bagakit/researcher/topics/product/cue-sync-portability/claims.md#c001` — supported: Copper public discussion directly supports local/private behavior, export or external editing, and programmatic access; it does not independently establish broad demand for positive sync or iPhone support.
- `.bagakit/researcher/topics/product/cue-sync-portability/claims.md#c002` — supported: The current evidence threshold is not met for selecting CloudKit, an account backend, or an iPhone client as the next implementation slice.
- `.bagakit/researcher/topics/product/cue-sync-portability/claims.md#c003` — supported: Comparable Joplin reports show that offline edits, deletion, attachments and binary-resource conflict handling fail independently and must preserve both sides.
- `.bagakit/researcher/topics/product/cue-sync-portability/claims.md#c004` — supported: A cue package should remain the only mutable workspace truth; per-item Markdown records are authoritative, while cue.md is an explicit single-record import or export snapshot and never a live replica.
- `.bagakit/researcher/topics/product/cue-sync-portability/claims.md#c005` — supported: Cue schema 2 is not safe to market as reliable Mac-to-Mac sync because manifest membership, uncoordinated fingerprint CAS, wall-clock tombstones and immediate asset deletion can lose or hide concurrent work.
- `.bagakit/researcher/topics/product/cue-sync-portability/claims.md#c006` — supported: On macOS 14, explicit screenshots should use SCScreenshotManager for one-shot in-memory capture; Cue owns the region overlay and window identity selection needed for fail-closed privacy gating.
- `.bagakit/researcher/topics/product/cue-sync-portability/claims.md#c007` — supported: Screenshot attachments cannot be safely layered onto the current WorkspaceStore because document and fingerprint are not one snapshot, CAS has a TOCTOU gap, multi-file publication can expose hybrid packages, and recovery snapshots omit asset bytes.
- `.bagakit/researcher/topics/product/cue-sync-portability/claims.md#c008` — supported: Attachment metadata should reference immutable content-addressed PNG bytes; refcounts derive from retained WorkItems, and Undo, Recovery, Archive, Conflict Copy and safe merge all protect the asset closure before delayed garbage collection.
- `.bagakit/researcher/topics/product/cue-sync-portability/claims.md#c009` — supported: Pewter and Nickel supply audited selection, panel, HUD, composer and packaging patterns but no screenshot attachment, Copy Image or Drag File implementation.
- `.bagakit/researcher/topics/product/cue-sync-portability/claims.md#c010` — supported: Future Cue CLI, macOS app and iPhone client must share one Foundation-only CueCore codec and coordinated transaction API rather than reimplement storage per client.
- `.bagakit/researcher/topics/product/cue-sync-portability/claims.md#c011` — supported: Read-only automation can consume an open local file or JSON format without sharing Cue's writer transaction core.
- `.bagakit/researcher/topics/product/cue-sync-portability/claims.md#c012` — supported: SCContentSharingPicker provides native window, app and display selection, but macOS 14 has no region mode and Cue cannot rely on its callback for pre-capture window identity privacy inspection.
- `.bagakit/researcher/topics/product/cue-sync-portability/claims.md#c013` — supported: Immediate last-reference asset deletion and document-only Undo are simpler and smaller than retained asset closure, but they cannot restore byte-exact screenshots after Undo or conflict recovery.
- `.bagakit/researcher/topics/product/cue-sync-portability/claims.md#c014` — supported: Obsidian demonstrates that a user-owned folder of plain Markdown files can be a successful mutable workspace model without an Apple document package.

## Topic Coverage
- `product/cue-sync-portability` — `.bagakit/researcher/topics/product/cue-sync-portability/index.md`
