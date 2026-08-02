# Claims

## c001

- kind: `observation`
- status: `supported`
- confidence: `high`

### Statement

Copper public discussion directly supports local/private behavior, export or external editing, and programmatic access; it does not independently establish broad demand for positive sync or iPhone support.

### Evidence Refs
- originals/x01.md
- originals/x02.md
- originals/x03.md
- originals/x04.md
- originals/x05.md
- originals/x06.md

### Counterevidence Refs
- originals/x07.md

### Bagakit Implication

Cue should prioritize open portability and a shared CLI contract before choosing a cloud backend.

## c002

- kind: `inference`
- status: `supported`
- confidence: `medium`

### Statement

The current evidence threshold is not met for selecting CloudKit, an account backend, or an iPhone client as the next implementation slice.

### Evidence Refs
- claims.md#c001
- charter.md

### Counterevidence Refs
- none recorded

### Bagakit Implication

Keep provider and mobile implementation as explicit non-goals until direct demand and conflict tests justify them.

## c003

- kind: `observation`
- status: `supported`
- confidence: `high`

### Statement

Comparable Joplin reports show that offline edits, deletion, attachments and binary-resource conflict handling fail independently and must preserve both sides.

### Evidence Refs
- originals/j01.md
- originals/j02.md
- originals/j03.md
- originals/j04.md

### Counterevidence Refs
- none recorded

### Bagakit Implication

Cue must treat record revisions, tombstones and asset closure as explicit sync semantics.

## c004

- kind: `recommendation`
- status: `supported`
- confidence: `high`

### Statement

A cue package should remain the only mutable workspace truth; per-item Markdown records are authoritative, while cue.md is an explicit single-record import or export snapshot and never a live replica.

### Evidence Refs
- originals/f01.md
- originals/f02.md
- originals/f04.md
- .bagakit/feature-tracker/features/f-222j2ekp8/proposal.md

### Counterevidence Refs
- claims.md#c014

### Bagakit Implication

This preserves openness without creating a second writer or confusing workspace identity.
## c005

- kind: `inference`
- status: `supported`
- confidence: `high`

### Statement

Cue schema 2 is not safe to market as reliable Mac-to-Mac sync. The shipped
code uses manifest membership, obtains the decoded document and fingerprint in
separate reads, checks the fingerprint before later sequential writes, and
uses wall-clock tombstones; together those observed mechanisms leave
concurrent overwrite and hybrid-package risks. Schema 2 has no attachment
lifecycle, so no asset deletion behavior is shipped or qualified.

### Evidence Refs
- Sources/Cue/WorkspacePackageCodec.swift
- Sources/Cue/WorkspaceStore.swift
- Sources/Cue/AppModel.swift
- originals/f03.md
- originals/j01.md
- originals/j03.md
- originals/j04.md

### Counterevidence Refs
- none recorded

### Bagakit Implication

The storage transaction and merge invariants must be repaired before provider enablement.

## c006

- kind: `recommendation`
- status: `supported`
- confidence: `high`

### Statement

On macOS 14, explicit screenshots should use SCScreenshotManager for one-shot in-memory capture; Cue owns the region overlay and window identity selection needed for fail-closed privacy gating.

### Evidence Refs
- originals/s01.md
- originals/s02.md
- originals/s03.md
- originals/s04.md

### Counterevidence Refs
- claims.md#c012

### Bagakit Implication

Capture, PNG validation and one storage commit belong behind one ScreenshotCaptureService owner.
## c007

- kind: `inference`
- status: `supported`
- confidence: `high`

### Statement

Screenshot attachments cannot be safely layered onto the current
`WorkspaceStore`: its observed split document/fingerprint read, pre-write CAS,
and sequential record publication create snapshot, race, and hybrid-package
risks, while current recovery snapshots carry only the document model and no
asset closure.

### Evidence Refs
- Sources/Cue/WorkspaceStore.swift
- Sources/Cue/AppModel.swift
- .bagakit/feature-tracker/features/f-222j2ekp8/proposal.md
- originals/f03.md
- originals/j02.md

### Counterevidence Refs
- none recorded

### Bagakit Implication

Implement coordinated staged-package replacement and complete asset closure before screenshot UI.
## c008

- kind: `recommendation`
- status: `supported`
- confidence: `high`

### Statement

Attachment metadata should reference immutable content-addressed PNG bytes; refcounts derive from retained WorkItems, and Undo, Recovery, Archive, Conflict Copy and safe merge all protect the asset closure before delayed garbage collection.

### Evidence Refs
- claims.md#c003
- claims.md#c007
- originals/j02.md
- originals/j04.md

### Counterevidence Refs
- claims.md#c013

### Bagakit Implication

This prevents dangling previews and irreversible image loss across conflicts and Undo.
## c009

- kind: `observation`
- status: `supported`
- confidence: `high`

### Statement

Pewter and Nickel supply audited selection, panel, HUD, composer and packaging patterns but no screenshot attachment, Copy Image or Drag File implementation.

### Evidence Refs
- originals/r01.md
- originals/r02.md
- THIRD_PARTY_NOTICES.md

### Counterevidence Refs
- none recorded

### Bagakit Implication

Cue should attribute transfer behavior to Apple public contracts and its own tests, not expand third-party provenance.

## c010

- kind: `recommendation`
- status: `supported`
- confidence: `high`

### Statement

Future Cue CLI, macOS app and iPhone client must share one
UI-framework-free `CueCore` codec and coordinated transaction API rather than
reimplement storage per client. The shared target uses Foundation plus the
existing Apple CryptoKit SHA-256 implementation and excludes AppKit, SwiftUI,
and Combine.

### Evidence Refs
- originals/x05.md
- originals/x06.md
- originals/f03.md
- originals/m01.md
- originals/m02.md
- originals/m03.md

### Counterevidence Refs
- claims.md#c011

### Bagakit Implication

Shared writer semantics are a prerequisite for safe automation and cross-device documents.
## c011

- kind: `observation`
- status: `supported`
- confidence: `high`

### Statement

Read-only automation can consume an open local file or JSON format without sharing Cue's writer transaction core.

### Evidence Refs
- originals/x06.md
- originals/f01.md

### Counterevidence Refs
- none recorded

### Bagakit Implication

A read-only cue CLI can arrive before coordinated mutation commands.

## c012

- kind: `observation`
- status: `supported`
- confidence: `high`

### Statement

SCContentSharingPicker provides native window, app and display selection, but macOS 14 has no region mode and Cue cannot rely on its callback for pre-capture window identity privacy inspection.

### Evidence Refs
- originals/s03.md

### Counterevidence Refs
- none recorded

### Bagakit Implication

The system picker remains a simpler option only where identity-dependent privacy gating is not required.

## c013

- kind: `inference`
- status: `supported`
- confidence: `high`

### Statement

Immediate last-reference asset deletion and document-only Undo are simpler and smaller than retained asset closure, but they cannot restore byte-exact screenshots after Undo or conflict recovery.

### Evidence Refs
- Sources/Cue/AppModel.swift
- Sources/Cue/WorkspaceStore.swift
- claims.md#c003

### Counterevidence Refs
- none recorded

### Bagakit Implication

Cue accepts delayed garbage collection complexity because recoverability is a hard product invariant.

## c014

- kind: `observation`
- status: `supported`
- confidence: `high`

### Statement

Obsidian demonstrates that a user-owned folder of plain Markdown files can be a successful mutable workspace model without an Apple document package.

### Evidence Refs
- originals/f01.md

### Counterevidence Refs
- none recorded

### Bagakit Implication

Cue's package recommendation is a product-specific identity and asset boundary, not a universal Markdown rule.

## c015

- kind: `observation`
- status: `supported`
- confidence: `high`

### Statement

Apple documents `FileManager.replaceItemAt` as a same-volume, no-data-loss
replacement API, recommends an OS replacement directory or a unique
same-parent item, and supports retaining a named backup. Apple documents
`NSFileCoordinator` accessors for files/directories and file packages, but
neither contract supplies Cue's semantic revision check or states a
power-loss/directory-fsync guarantee.

### Evidence Refs
- originals/f05.md
- originals/f06.md

### Counterevidence Refs
- originals/f07.md

### Bagakit Implication

Foundation supplies the project-native coordination and safe-replacement
primitives, while Cue must own snapshot revision, stage validation, conflict,
and recovery semantics and must not inherit stronger syscall claims.

## c016

- kind: `observation`
- status: `supported`
- confidence: `medium`

### Statement

On one macOS 26.3.2 APFS host, Cue's checked-in standalone probe observed a
pre-publication process abort leaving complete live-old plus staged-new and no
backup, and an immediate post-publication process abort leaving complete
live-new plus retained backup-old. Two independent
`NSFileCoordinator(options: [])` writers using one expected generation
produced exactly one success and one conflict.

### Evidence Refs
- originals/f08.md
- originals/f08-package-publication-probe.swift

### Counterevidence Refs
- originals/f08.md#limitations

### Bagakit Implication

The selected composition is testable for T-006 application/process failpoints
and participating-process CAS, but the observation is not filesystem-general,
power-loss qualification, dual-Mac qualification, or shipped behavior.

## c017

- kind: `recommendation`
- status: `supported`
- confidence: `medium`

### Statement

Cue T-006 should build and fully validate a hidden same-parent staged package,
then inside one `NSFileCoordinator` write accessor with `options: []` recheck
the exact live revision and publish through `FileManager.replaceItemAt` with a
named retained backup. Post-publication failure preserves live and displaced
packages for typed recovery; it never removes live and copies a backup back.

### Evidence Refs
- claims.md#c015
- claims.md#c016
- originals/f05.md
- originals/f06.md

### Counterevidence Refs
- originals/f07.md
- originals/f08.md#limitations

### Bagakit Implication

Promise and test complete old-or-new packages under named application/process
failpoints. Do not claim undocumented power-cut durability or reliable sync,
and do not replace the Foundation writer with a Darwin-specific implementation.
