# Goal Supervisor

## Role Boundary
- Inner loop: execute one bounded step toward the foreground Goal.
- Supervisor checkpoint: observe evidence, detect drift, and update the Goal or
  execution owner before more implementation.
- Do not become a second executor.

## Checkpoint Cadence
- Run before each bounded execution round.
- Run after each bounded execution round.
- Run before claiming `status: complete`.

## Drift Classes
- target drift
- method drift
- scope drift
- evidence drift
- retry drift
- risk drift
- context drift

## Packet Ownership
- Store the current supervisor packet and execution evidence in the foreground
  Goal's `execution_owner` surface.
- Goal events may point to a packet only when it changes Kernel direction,
  lifecycle, or a user gate. Do not copy packet state into this file.

## Evolver Review Checkpoints
- Use event-bound review triggers: `before_round`, `after_round`, `risk`,
  `stale`, `pre_closeout`, or opportunistic `session_end`.
- `stale` means expected evidence is missing; do not add a timer or daemon.
- Store request/receipt state under `.bagakit/goal/reviews/`; Goal does not own
  Evolver topic, adoption, routing, or promotion state.

## Rules
- Classify waiting, blockers, loss lines, and no-progress rounds in the
  execution owner. Goal may mirror only the coarse lifecycle status needed for
  multi-Goal scheduling.
- Patch the Goal only when new information changes execution direction or
  recovery.
- Ask before changing the promised outcome, dropping a requirement, or taking
  irreversible, privacy-sensitive, publication, or cost-bearing action.
- Distill sidecar output into a Goal delta, risk, non-goal, acceptance
  criterion, open question, or owner-file pointer.
