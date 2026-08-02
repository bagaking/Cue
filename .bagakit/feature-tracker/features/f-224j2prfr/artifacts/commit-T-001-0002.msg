feature(f-224j2prfr): task(T-001) Fix hidden engagement poisoning and terminal pointer rearm with public AppKit regressions.

Plan:
- Feat Goal: Ensure every visible unpinned Cue instance reliably yields screen space after the user disengages, collapsing into a small reachable edge target without losing drafts, focus safety, drag/resize safety, multi-display reachability, or explicit reveal behavior; verify the packaged runtime, commit through Tracker, restart, and push the exact build.
- Task: Repair reliable idle edge retraction at the existing owner

Check:
- `sh scripts/check.sh` => PASS

Learn:
- Add key learnings, risks, or follow-up notes here.

Feature-ID: f-224j2prfr
Task-ID: T-001
Gate-Result: pass
Task-Status: done
