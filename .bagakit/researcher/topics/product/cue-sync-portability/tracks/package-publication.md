# package-publication

## Track Contract

- track id: `package-publication`
- parent pass: `pass-002`
- parent charter: `charter.md`

## Track Question

bound same-parent package replacement, coordination, backup retention, failpoints, and durability claims

## Required Source Types
- official Apple Foundation documentation plus local macOS experiment and one lower-level counterevidence source

## Preferred Sources
- Current Apple Developer Documentation for `FileManager.replaceItemAt`,
  `withoutDeletingBackupItem`, and `NSFileCoordinator` directory/file-package
  accessors; the installed Darwin `rename(2)` manual only as a lower-level
  boundary; a checked-in probe run as independent processes on the target Mac.

## Disallowed Sources
- Provider marketing, generic filesystem advice, an undocumented assumption
  that Foundation calls a particular Darwin syscall, or a process-kill result
  restated as power-loss durability.

## Source Id Range

f05 through f08

## Owned Output Files
- tracks/package-publication.md
- originals/f05.md through originals/f08.md
- originals/f08-package-publication-probe.swift
- summaries/f05.md through summaries/f08.md

## Minimum Evidence
- One official source for safe same-volume replacement and retained backup;
  one official source for coordinated directory/package reads and writes;
  one lower-level counterexample to overclaiming; and one reproducible local
  run covering successful replacement, pre/post-publication process stops,
  and two independent expected-revision writers.

## Lead Policy

Follow only evidence that can change the selected Foundation-only publication primitive or the honesty boundary; do not expand into provider or filesystem surveys.

## Drift Check

Distinguish official API contract, Darwin contract, local process experiment, Cue inference, and shipped capability; never claim power-loss durability or reliable sync from process-level observations.

## Merge Notes
- The integration writer alone updates shared claims, synthesis, disposition, and implementation contract after source-bound evidence is reviewed.
