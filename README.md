# Cue

Cue is a quiet, native macOS work queue for the fragments and prompts you want to use next with ChatGPT, Claude, Cursor, a browser, or a terminal.

It combines intentional selected-text capture, typed future prompts, explicit completion, batch copy, merge, Archive, and human-readable local workspace packages in one compact sidecar. Cue does not run an account service, upload note content, passively record clipboard or screen history, or inject text into other apps.

## Requirements

- macOS 14 or newer
- Apple Swift toolchain 5.10 or newer
- Accessibility permission only for selected-text capture and the double-Shift shortcut; all typed queue features work without it

## Build

```bash
swift build
sh scripts/check.sh
sh scripts/package_app.sh
open dist/Cue.app
```

The packaged app is written to `dist/Cue.app`. The first run offers a one-click local `.cue` workspace in `~/Documents/Cue/`, or you can choose an existing Cue workspace package.

For repeatable UI experiments, launch the packaged executable with an explicit visible panel while keeping normal login launch quiet:

```bash
dist/Cue.app/Contents/MacOS/Cue --show
```

With text selected in another native app, this starts a two-second QA countdown. Return focus to the selected app before the countdown ends; Cue then invokes the exact explicit-capture handler without synthesizing copy or paste events:

```bash
dist/Cue.app/Contents/MacOS/Cue --capture-selection
```

## Data contract

- One `.cue` package per workspace is the source of truth. Every WorkItem has its own readable Markdown document under `items/YYYY/MM/`.
- `manifest.yaml` and `sections/*.yaml` describe workspace structure; `tombstones/*.json` propagate physical deletion; `assets/sha256/` is reserved for content-addressed attachments.
- Settings live in `~/Library/Application Support/Cue/settings.json`.
- Rebuildable search indexes live under `~/Library/Caches/Cue/WorkspaceIndex/`; they are never source of truth.
- Timestamped package backups live beside the workspace in `.cue-backups/`.
- Changed package files use sibling temporary files, `fsync`, parse validation, and atomic replacement; the manifest is committed last.
- External edits stop writes and surface Reload / Save Copy / safe three-way Merge choices. Non-overlapping item and section changes can be previewed together; same-object conflicts stop without touching the external package.

See [docs/PRODUCT.md](docs/PRODUCT.md) for commands, trust boundaries, and acceptance criteria.
See [docs/EXPERIMENTS.md](docs/EXPERIMENTS.md) for a five-minute smoke test,
Copper-versus-Cue comparison protocol, and trust-boundary probes.
