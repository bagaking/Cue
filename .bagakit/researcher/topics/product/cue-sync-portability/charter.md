# Topic Charter

## Core Question

Which sync, portability, mobile-capture, and screenshot behaviors are supported by attributable user evidence and fit Cue's local-first trust contract?

## Decision Or Downstream Use

Decide the T-001 architecture and market-requirement section of Feature
`f-222j2ekp8`, then constrain the attachment, capture, and interaction tasks.
Research must not select or implement a sync provider in this increment.

## Output Shape

Attributable source cards and summaries, a claim ledger that distinguishes
observation from inference, and a concise handoff into the reviewed Feature
Tracker proposal.

## In Scope
- Copper owner statements and public user replies about sync, mobile, export,
  attachments, conflicts, offline behavior, and privacy.
- Comparable capture and notes-tool user evidence for the same jobs and failure
  modes.
- Primary package/Markdown format contracts relevant to `.cue` and `.cue.md`.
- Apple-native explicit region/window capture APIs and audited open-source
  implementation evidence.

## Out Of Scope
- Generic feature-list comparisons or unsourced market rankings.
- Choosing CloudKit, an account backend, or an iPhone implementation before
  requirements are stable.
- OCR, passive screen history, automatic upload, and background capture.
- Treating owner launch copy as independent user demand.

## Source Priority
- Direct attributable user statements for demand and failure stories.
- Product-owner replies for intended behavior, labelled as owner claims.
- Primary Apple and file-format documentation for owned API/format behavior.
- Audited source code for implementation patterns, never as market-demand proof.

## Evidence Threshold

A product priority needs either two independent attributable user statements or
one Copper user statement plus one independent comparable-tool statement.
Architecture recommendations need primary behavior documentation, a stated
inference, limitations, and a transfer check against Cue's current package.

## Stop Conditions
- Each decision has direct evidence or is explicitly marked inference; remaining gaps cannot change the screenshot slice or .cue compatibility direction.

## Drift Sentinels
- Stop any lane that becomes a generic notes-app survey or implementation
  tutorial without bearing on Cue's trust, package, sync, or explicit-capture
  decisions.
- Preserve inaccessible or ambiguous replies as coverage gaps, not evidence.
