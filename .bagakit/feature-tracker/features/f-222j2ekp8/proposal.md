# Feature Proposal: f-222j2ekp8

## Why
- Cue 0.2.0 has the correct per-item package foundation, but image capture, attachment interactions and market-grounded synchronization are not implemented.
- The user wants real public user discussion—not feature imitation—to determine sync, mobile and portability priorities.
- `.cue.md` must improve interoperability without reviving one aggregate workspace file or introducing a second source of truth.

## Goal
- Ship explicit region/window screenshot attachments with preview, Copy Image and Drag File while preserving one source of truth; ground sync requirements in real user evidence; define a non-confusing .cue and .cue.md compatibility contract; exclude OCR, passive capture and automatic upload.

## Principle Layer
- What: Cue explicitly captures one user-chosen screen region or window into the same bounded work-item lifecycle and stores each image once by content hash.
- Why: Intentional visual context is a high-value next-work fragment; passive screen memory would change Cue's trust contract and category.
- Intended generalization: text, URLs and images may share one attachment-aware WorkItem contract across Mac CLI, Mac-to-Mac sync and a lightweight iPhone companion.
- Failure boundary: no background recording, automatic upload, OCR in this slice, duplicate source of truth, aggregate-workspace fallback, silent permission request, orphaned deletion or metadata-only test claims.
- Behavior examples:
  - Region and Window commands are explicit and visibly permission-gated.
  - A captured PNG appears on one WorkItem and supports preview, Copy Image and file drag.
  - Removing the last visible attachment reference enters a recoverable delayed-GC lifecycle; Undo, Recovery, Archive and conflict copies continue to protect the bytes.
  - `.cue` remains the only mutable workspace package; `.cue.md` is a one-record import/export snapshot and is never watched or synchronized as a live replica.
- Evidence refs:
  - `docs/PRODUCT.md`
  - `docs/EXPERIMENTS.md`
  - `.bagakit/researcher/topics/product/cue-sync-portability/summaries/synthesis-001.md`
  - `.bagakit/researcher/topics/product/cue-sync-portability/claims.md`

## Scope
- In scope:
  - public-user evidence for sync, mobile capture, attachments, conflicts, portability and privacy;
  - `.cue` / `.cue.md` compatibility decision;
  - a coordinated schema-3 package transaction and shared Foundation-only storage core before attachments;
  - native explicit region/window screenshot capture;
  - content-addressed PNG attachments inside `.cue/assets/sha256/`;
  - item preview, Copy Image and Drag File;
  - attachment deletion/refcount/tombstone behavior appropriate to the package model;
  - deterministic core, integration and Release visual/runtime evidence.
- Out of scope:
  - OCR, passive/background screen capture, screen history and automatic upload;
  - full iPhone workspace editor;
  - claiming reliable Mac-to-Mac sync, selecting CloudKit, or adding an account backend before dual-device conflict qualification;
  - a second SQLite or aggregate Markdown source of truth;
  - unrelated Context Stack visual redesign.

## Evidence-Backed Product Decisions

### Market signal

- Copper discussion directly supports local/private ownership, external editing or export, and programmatic JSON/CLI access.
- Copper owner posts describe no account, no sync and attachment roadmap intent, but owner claims are not independent user demand.
- The retained Copper discussion does not meet the evidence threshold for prioritizing positive sync, iPhone, offline or conflict UX. These remain open leads rather than implied market requirements.
- Joplin user issues independently prove concrete failure classes: non-overlapping offline edits can still conflict; attachment conflicts need their own semantics; delete conflicts can cascade into mobile/sync failures; binary conflict handling must copy rather than move bytes.
- A second comparable-product source is still missing. Cue may use the Joplin issues as failure-mode evidence, not as prevalence evidence.

### One compatibility contract

- `<name>.cue` is the one mutable workspace SSOT and remains an Apple document package.
- Package records use one self-describing Markdown codec; `items/YYYY/MM/<item-id>.cue.md` is the authoritative per-item record inside the package.
- A `.cue.md` outside the package is an explicit one-record import/export snapshot. It is not a workspace, not watched, and not bidirectionally synchronized.
- Cue owns one namespaced `cue` frontmatter key and must round-trip unknown user frontmatter and body bytes. YAML frontmatter is a Cue convention, not part of CommonMark.
- Schema-2 packages remain readable. The first verified schema-3 write performs a coordinated migration; a newer unsupported schema is read-only and refuses destructive writeback.
- A single `.cue.md` does not promise to carry PNG bytes. The complete attachment-bearing transfer unit remains the `.cue` package.

### Sync-safety boundary

- Membership comes from enumerating the item directory. The manifest keeps workspace identity/schema/title and must not be an authoritative list of every item or section.
- Record identity is `workspace_id + item_id + record revision/hash`; asset identity is exact-byte SHA-256. Paths are derived addresses, not identity.
- Delete operations bind the observed record revision/hash. Wall-clock last-write-wins is forbidden for edit/delete conflicts.
- Same identity and revision must mean the same bytes. Divergent bytes preserve both sides as an explicit conflict; no silent merge or overwrite.
- Assets are written and verified before referencing metadata is published. Missing/corrupt assets remain visible typed errors. Physical GC waits for retention and convergence evidence.
- App, future CLI and future iPhone client share one Foundation-only `CueCore` codec and coordinated transaction API. File transport alone does not make a safe multi-client product.
- Until two-Mac offline edit/delete/attachment tests pass, Cue may say the format has sync-friendly object boundaries; it may not claim reliable Mac-to-Mac sync.

### Native screenshot boundary

- macOS 14 uses `SCScreenshotManager.captureImage` for a one-shot in-memory image. Cue does not start a continuous `SCStream`, shell out, or use deprecated/private capture APIs.
- Window capture uses a Cue-owned selector over `SCShareableContent.windows` so bundle/PID/window identity is available before the fail-closed privacy gate.
- macOS 14 has no system region picker. Region capture uses a Cue-owned overlay to choose a display-local rect, then a display filter plus `SCStreamConfiguration.sourceRect`.
- Accessibility denial, incomplete identity mapping, timeout, secure field, protected content or denylisted app produces zero PNG bytes and zero package mutation.
- One invocation epoch owns selection, privacy gate, capture, PNG verification, storage commit and terminal UI/focus restoration; late or duplicate callbacks are inert.

### Storage gate before attachment UI

- Current `WorkspaceStore` cannot safely accept PNG attachments unchanged: load/fingerprint are not one snapshot, CAS has a TOCTOU window, sequential publication can expose hybrid packages, rollback removes live before restore, and Undo/Recovery/Conflict Copy carry no asset bytes.
- The next implementation plan must start with a coordinated staged-package transaction: write and verify immutable blobs, publish metadata, validate the complete package, then atomically replace the live package while preserving a valid prior package.
- Attachment refcounts are derived from retained WorkItems, never stored as mutable counters. Archive, Undo, Recovery and conflict originals are protected references.
- Preview, Copy Image, Drag File and Remove remain downstream of that storage contract. Text-only card density must remain unchanged.

## Acceptance Criteria
- Capture is impossible without an explicit command and permission failure persists zero image bytes.
- Region and Window capture both create valid content-addressed PNG assets and attachment metadata that round-trips through the package.
- Duplicate image bytes deduplicate by SHA-256; deletion does not orphan or prematurely remove shared assets.
- WorkItem UI previews images and exposes Copy Image and Drag File with keyboard/VoiceOver-accessible actions.
- Search/cache data remains derived; package Markdown and attachment metadata remain the only content truth.
- `.cue.md` support, if implemented, has one authoritative direction and cannot race the `.cue` package.
- Directory-derived membership, revision-bound tombstones, coordinated publication and complete asset closure pass deterministic conflict/crash tests before any sync claim.
- Automated checks plus Release renders cover success, denial, missing asset, duplicate asset and deletion cases.

## Transfer Checks
- The attachment contract is readable by a future CLI and iPhone companion without importing AppKit UI types.
- Mac-to-Mac file sync can merge independent item documents and propagate tombstones without syncing a mutable database.
- App, CLI and future iPhone clients consume the same storage owner; no client carries a second codec or writer truth.
- Removing screenshot UI does not make text-only workspaces unreadable or strand required storage state.

## Impact
- Code paths: WorkItem/attachment model, package codec/store, capture service, app command wiring, item card, settings/privacy copy and preview renderer.
- Tests: core package round-trip/dedup/deletion, integration capture outcomes and copy/drag contracts, Release renders, manual Screen Recording permission and real drag probe.
- Rollout notes: Cue 0.2.0 is the stable baseline. Replan the remaining tasks so coordinated schema-3 storage and attachment closure land before capture and UI; keep provider selection and sync claims out of this increment.
