# Cue — Agent Contract

## Product principle

Cue captures an explicit selected fragment or unsent prompt with minimal interruption, keeps it in one bounded local work queue, and makes reuse plus completion deliberate and recoverable.

## Hard boundaries

- Native macOS 14+ only; SwiftUI/AppKit and Apple frameworks are the project-native route.
- No account, cloud content sync, telemetry, passive clipboard history, passive screen capture, or arbitrary-app Send injection.
- Accessibility access is used only after an explicit capture command. Typed capture must remain useful without it.
- Each `.cue` package is the content source of truth: `manifest.yaml`, one readable Markdown file per WorkItem, section records, tombstones, and content-addressed assets. Settings and rebuildable search caches may store paths or derived data, never a parallel item database.
- Never silently overwrite an externally edited workspace. Never silently fall back to clipboard content when selected-text capture fails.
- Secure fields and denylisted apps persist zero captured content.
- Copying does not complete by default. All destructive-looking lifecycle actions must be recoverable through Undo or Archive restore.

## Build and proof

```bash
swift build
sh scripts/check.sh
sh scripts/package_app.sh
open dist/Cue.app
```

Behavior tests should cover per-item Markdown round trips, package structure, tombstone deletion, rebuildable indexes, atomic writes, external-edit conflicts, backup retention, duplicate suppression, merge, completion, archive/restore, responsive minimum-size renders, and undo snapshots.
