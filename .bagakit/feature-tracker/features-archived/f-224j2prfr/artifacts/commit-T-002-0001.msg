feature(f-224j2prfr): task(T-002) Keep rail clicks anchored to their edge and qualify the packaged retraction lifecycle.

Plan:
- Feat Goal: Ensure every visible unpinned Cue instance reliably yields screen space after the user disengages, collapsing into a small reachable edge target without losing drafts, focus safety, drag/resize safety, multi-display reachability, or explicit reveal behavior; verify the packaged runtime, commit through Tracker, restart, and push the exact build.
- Task: Package, restart and qualify the exact edge build

Check:
- `sh scripts/check.sh` => PASS

Learn:
- Add key learnings, risks, or follow-up notes here.

Feature-ID: f-224j2prfr
Task-ID: T-002
Gate-Result: pass
Task-Status: done
