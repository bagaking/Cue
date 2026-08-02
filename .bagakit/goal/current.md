# Current Goal

Read `.bagakit/goal/state.yaml`, resolve `foreground_goal`, then read that Goal
Kernel and its `execution_owner` before acting. Read current task, next action,
blockers, waits, and evidence from that owner rather than from the Goal file.

If `.bagakit/goal/supervisor.md` exists, read it before
execution and run its checkpoint rules.

Context may be stale or wrong; recover from these files before trusting prior context.
