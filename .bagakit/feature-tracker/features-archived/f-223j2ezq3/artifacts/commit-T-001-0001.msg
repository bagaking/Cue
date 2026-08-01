feature(f-223j2ezq3): task(T-001) Ship single-window edge retraction, Panel Pin, focus-safe hover reveal and deterministic policy/geometry checks.

Plan:
- Feat Goal: Make Cue visually disappear when idle without becoming hard to recover: add a distinct panel Pin, edge retract, hover reveal, bounded delay and multi-display-safe geometry; then package, restart, commit and push the stable build.
- Task: Implement the single-owner edge retract contract

Check:
- `sh scripts/check.sh` => PASS

Learn:
- Add key learnings, risks, or follow-up notes here.

Feature-ID: f-223j2ezq3
Task-ID: T-001
Gate-Result: pass
Task-Status: done
