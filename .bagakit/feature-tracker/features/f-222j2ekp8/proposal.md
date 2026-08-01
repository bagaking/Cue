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
  - Deleting the last attachment reference removes the asset through a recoverable or explicitly tested lifecycle.
  - `.cue` remains the workspace package; any `.cue.md` support must be an unambiguous Markdown interchange or item-document surface, not a second live workspace database.
- Evidence refs:
  - `docs/PRODUCT.md`
  - `docs/EXPERIMENTS.md`
  - `.bagakit/feature-tracker/features/f-222j2ekp8/proposal.md`

## Scope
- In scope:
  - public-user evidence for sync, mobile capture, attachments, conflicts, portability and privacy;
  - `.cue` / `.cue.md` compatibility decision;
  - native explicit region/window screenshot capture;
  - content-addressed PNG attachments inside `.cue/assets/sha256/`;
  - item preview, Copy Image and Drag File;
  - attachment deletion/refcount/tombstone behavior appropriate to the package model;
  - deterministic core, integration and Release visual/runtime evidence.
- Out of scope:
  - OCR, passive/background screen capture, screen history and automatic upload;
  - full iPhone workspace editor;
  - built-in account service or CloudKit before file-sync evidence shows a need;
  - a second SQLite or aggregate Markdown source of truth;
  - unrelated Context Stack visual redesign.

## Acceptance Criteria
- Capture is impossible without an explicit command and permission failure persists zero image bytes.
- Region and Window capture both create valid content-addressed PNG assets and attachment metadata that round-trips through the package.
- Duplicate image bytes deduplicate by SHA-256; deletion does not orphan or prematurely remove shared assets.
- WorkItem UI previews images and exposes Copy Image and Drag File with keyboard/VoiceOver-accessible actions.
- Search/cache data remains derived; package Markdown and attachment metadata remain the only content truth.
- `.cue.md` support, if implemented, has one authoritative direction and cannot race the `.cue` package.
- Automated checks plus Release renders cover success, denial, missing asset, duplicate asset and deletion cases.

## Transfer Checks
- The attachment contract is readable by a future CLI and iPhone companion without importing AppKit UI types.
- Mac-to-Mac file sync can merge independent item documents and propagate tombstones without syncing a mutable database.
- Removing screenshot UI does not make text-only workspaces unreadable or strand required storage state.

## Impact
- Code paths: WorkItem/attachment model, package codec/store, capture service, app command wiring, item card, settings/privacy copy and preview renderer.
- Tests: core package round-trip/dedup/deletion, integration capture outcomes and copy/drag contracts, Release renders, manual Screen Recording permission and real drag probe.
- Rollout notes: Cue 0.2.0 is the stable baseline. Land architecture/storage, capture owner, and UI/validation as small closed-loop commits; do not mix sync transport implementation into the screenshot slice.
