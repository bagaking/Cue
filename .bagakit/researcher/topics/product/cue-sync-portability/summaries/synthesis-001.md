# Cue portability, sync and screenshot synthesis

## Synthesis Contract

- synthesis id: `synthesis-001`
- parent charter: `charter.md`

## What This Synthesizes

Evidence-backed product and architecture decisions for Copper-derived demand, cue and cue.md roles, Mac-to-Mac readiness, explicit screenshots, attachment storage, CLI and future iPhone clients.

## Claim Refs
- c001
- c002
- c003
- c004
- c005
- c006
- c007
- c008
- c009
- c010
- c011
- c012
- c013
- c014
- c015
- c016
- c017

## Insight Refs
- insights/i001.md
- insights/i002.md
- insights/i003.md
- insights/i004.md
- insights/i005.md

## Findings
- Copper evidence is strong for local privacy, export, external editing and programmatic access, but not yet strong enough to select a sync provider or iPhone implementation.
- One mutable cue package plus independently mergeable Markdown records is the stable direction; cue.md is a one-way import or export record, never a second live workspace.
- Reliable file sync requires coordinated snapshots, record revision or hash conflict semantics, observed-revision tombstones and delayed asset garbage collection.
- macOS 14 screenshots should use one-shot ScreenCaptureKit with Cue-owned region selection and fail-closed window identity privacy gating.
- Attachments are a storage and recoverability problem before they are a preview, pasteboard or drag interaction.
- Apple safe replacement plus package coordination support Cue's selected
  same-parent staged-publication design, and one local process experiment
  observed pre-publication live-old plus staged-new, post-publication live-new
  plus retained backup-old, and one winner for two coordinated
  expected-revision writers.
- Foundation documentation and that process experiment do not prove
  power-loss durability; Cue owns semantic CAS, typed recovery, and the
  application/process failpoint promise.

## Open Risks
- Only one comparable product currently has retained conflict evidence; lead l001 remains open.
- No dual-Mac offline conflict qualification has been run, so Cue must not claim reliable Mac-to-Mac sync.
- Window privacy mapping, Finder drag terminal behavior and attachment crash recovery remain implementation gates.
- T-006 still needs public store/AppModel failpoint and recovery tests. The
  publication experiment is design evidence, not proof that schema 3 shipped.
- Power-cut, alternate-filesystem, non-participating-writer, and dual-Mac
  behavior remain unqualified and cannot support a reliable-sync claim.

## Downstream Disposition

- Claims c001 through c014 were consumed by Feature f-222j2ekp8 proposal and
  reviewed task-plan revision 2.
- The resulting order is storage transaction and codec first, then attachment
  closure, capture, transfer UI, and qualification.
- Pass 002 locks the T-006 publication direction to a hidden same-parent stage,
  full validation, `NSFileCoordinator(options: [])`, final revision check,
  Foundation safe replacement, and a retained displaced package. It explicitly
  rejects remove-copy rollback, a Darwin-specific writer, and power-loss or
  reliable-sync claims.
- Implementation and delivery status remain owned by the Feature receipt,
  state, and tasks; this research synthesis does not claim those capabilities
  have shipped.

## Track Evidence Coverage

- copper-discussion: originals/x01.md through originals/x07.md; summaries/x01.md through summaries/x07.md
- adjacent-demand: originals/j01.md through originals/j04.md; summaries/j01.md through summaries/j04.md
- capture-platform: originals/s01.md through originals/s04.md; summaries/s01.md through summaries/s04.md; originals/r01.md through originals/r02.md; summaries/r01.md through summaries/r02.md
- format-architecture: originals/f01.md through originals/f04.md; summaries/f01.md through summaries/f04.md; originals/m01.md through originals/m03.md; summaries/m01.md through summaries/m03.md
- package-publication: originals/f05.md through originals/f08.md;
  originals/f08-package-publication-probe.swift; summaries/f05.md through
  summaries/f08.md
