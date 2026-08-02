# format-architecture

## Track Contract

- track id: `format-architecture`
- parent pass: `pass-001`
- parent charter: `charter.md`

## Track Question

compare package and Markdown interoperability contracts and derive one-way .cue.md semantics

## Required Source Types
- Primary documentation or specifications for at least two package/Markdown
  interoperability models, plus direct inspection of Cue's package codec.

## Preferred Sources
- TextBundle/TextPack, Obsidian-style Markdown, file-package coordination, or
  comparable owner documentation with explicit authority boundaries.

## Disallowed Sources
- Format proposals that require a second mutable database or one aggregate
  workspace file; unsourced opinions about filename aesthetics.

## Source Id Range

`f01` through `f04` for format contracts and `m01` through `m03` for
future mobile document contracts.

## Owned Output Files
- tracks/format-architecture.md
- originals/f01.md through originals/f04.md
- summaries/f01.md through summaries/f04.md
- originals/m01.md through originals/m03.md
- summaries/m01.md through summaries/m03.md

## Minimum Evidence

Compare at least two primary format contracts and test the recommended
direction against Cue's manifest, per-item Markdown, tombstones, assets,
conflict detection, CLI, and future iPhone consumer.

## Lead Policy

Follow only specifications or implementations that clarify authority,
round-trip loss, package sync granularity, or filename/content-type behavior.

## Drift Check

The output must choose one authoritative `.cue`/`.cue.md` direction and name
what is not synchronized; it cannot end as a menu of options.

## Merge Notes
- Do not edit shared claims, insights, proposal, Tracker, or product code.
