# capture-platform

## Track Contract

- track id: `capture-platform`
- parent pass: `pass-001`
- parent charter: `charter.md`

## Track Question

verify Apple-native region/window capture APIs and audited open-source implementation patterns

## Required Source Types
- Primary Apple documentation for explicit region and window capture behavior,
  permissions, cancellation, and output types.
- Audited MIT-licensed macOS implementations relevant to native capture UX.

## Preferred Sources
- ScreenCaptureKit and macOS screenshot-service documentation; source at pinned
  commits with license and failure-path inspection.

## Disallowed Sources
- Shelling out to private or undocumented APIs as the product path; passive
  recording examples; clipboard fallbacks.

## Source Id Range

`s01` through `s04` for platform evidence and `r01` through `r02` for
audited implementation references.

## Owned Output Files
- tracks/capture-platform.md
- originals/s01.md through originals/s04.md
- summaries/s01.md through summaries/s04.md
- originals/r01.md through originals/r02.md
- summaries/r01.md through summaries/r02.md

## Minimum Evidence

Primary evidence must settle the project-native API boundary for both Region
and Window, explicit permission outcomes, cancellation, and zero-byte failure.
At least one audited open-source implementation must challenge the design.

## Lead Policy

Follow only API or source links needed to resolve selection ownership,
permission prompting, image encoding, or cancel/failure semantics.

## Drift Check

No recommendation may add background capture, OCR, automatic upload, shell
fallbacks, or a second window owner without explicit contradiction evidence.

## Merge Notes
- Do not edit shared claims, insights, proposal, Tracker, or product code.
