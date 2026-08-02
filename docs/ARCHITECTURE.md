# Cue architecture and truth map

This page answers stable questions: which component owns a behavior, where
truth lives, and which boundaries must survive future work. It deliberately
does not carry the current task, next action, release SHA, or research ledger;
those would go stale and already have canonical owners under `.bagakit/`.

## Cold-start reading order

Use this recovery chain instead of reconstructing the project from chat:

```text
AGENTS.md
  -> .bagakit/goal/current.md
  -> .bagakit/goal/state.yaml
  -> foreground Goal Kernel
  -> execution-owner receipt + state.json + tasks.json
  -> current task source_refs
  -> Researcher synthesis/claims when a decision needs evidence
  -> this architecture map
  -> Git diff, source, checks, package, live process
```

The layers answer different questions. Goal and Feature state say what to do;
Researcher says why; this page says where; code and proof say what is actually
true now.

## Runtime ownership

```text
CueMain
├── AppModel                         domain workflow and mutation orchestration
├── StatusItemController             menu-bar commands and application entry
├── FloatingPanelController          sole NSPanel state/frame/focus owner
│   └── PanelPresentation            pure presentation reducer + geometry policy
├── PanelRootView / SidecarView      SwiftUI composition and keyboard routing
│   ├── WorkItemCard                 item rendering and card actions
│   └── ComposerTextView             AppKit text-input bridge
├── SelectionCaptureService          explicit Accessibility selection reads
│   ├── ModifierTapMonitor            process-wide gesture observation
│   ├── secure/denylist checks         fail-closed before selected-text reads
│   └── CaptureHUD                    explicit result receipt
├── CapturePolicy                     normalized duplicate suppression
└── WorkspaceStore                   workspace load/write/conflict/recovery owner
    ├── WorkspacePackageCodec        `.cue` package records
    ├── MarkdownWorkspaceCodec       legacy aggregate Markdown for recovery,
    │                                merge, and internal migration
    └── WorkspaceSearchIndex         rebuildable derived search data
```

Ownership rules:

- `AppModel` is the application workflow boundary. Views request actions; they
  do not write workspace files or invent parallel lifecycle state.
- `FloatingPanelController` is the only owner allowed to mutate the retained
  `CuePanel` frame and presentation. `PanelPresentationMachine` and
  `PanelGeometryPolicy` keep its transition and geometry contracts testable
  without a second overlay window.
- `WorkspaceStore` and its codecs own persistence. Settings, caches, views,
  future CLI code, and future mobile code must not implement another record
  writer.
- `SelectionCaptureService` is invoked only by an explicit user command.
  Clipboard history, passive screen capture, arbitrary-app Send, and silent
  clipboard fallback remain outside the product boundary.

## Data truth

| Data | Canonical owner | Derived or non-authoritative surfaces |
|---|---|---|
| Workspaces, sections, WorkItems, tombstones, future attachment refs | one mutable `.cue` package | UI state, exports, backups, caches |
| App preferences and workspace paths | `SettingsStore` in Application Support | controls rendered from settings |
| Search results | `.cue` package content | `WorkspaceSearchIndex` under Library Caches |
| Product contract | `AGENTS.md` + `docs/PRODUCT.md` | README summaries |
| Active delivery state | foreground Goal's Feature owner | Goal prose, chat, status summaries |
| Research evidence | `.bagakit/researcher/topics/` | Researcher frontdoor/wiki indexes |
| Delivered runtime | Git commit + signed packaged executable hash + live PID | an old `dist/` directory by itself |

A `.cue.md` record is planned as explicit import/export interoperability. It is
not a live mirror of a `.cue` workspace and must never become a second mutable
truth.

## Current baseline versus planned platform

Do not blur these states when resuming work:

| Surface | Current shipped baseline | Planned, not shipped |
|---|---|---|
| Capture | explicit selected text and typed prompts | region/window screenshots |
| Workspace | schema-2 `.cue` package; one Markdown item record | coordinated schema-3 snapshot/CAS and shared frontmatter codec |
| Assets | content-addressed directory reserved | recoverable PNG attachment closure, preview, Copy Image, Drag File |
| Portability | human-readable local package and conflict UI | `cue` CLI, qualified Mac-to-Mac sync, provider selection, iPhone client |
| Panel | retained resizable panel, edge rail, hover/click reveal, Panel Pin | no separate panel roadmap implied by screenshot/sync research |

Schema 2 has useful per-file defenses and external-edit recovery, but it is not
a crash-consistent multi-file package transaction and must not be advertised as
reliable cross-device sync. The foreground Feature owns the schema-3 migration
order. Research conclusions are architecture inputs until their task gates and
code prove them.

## Critical behavior paths

### Capture and persistence

```text
explicit command
  -> selection/composer input
  -> CapturePolicy when external content is involved
  -> AppModel mutation
  -> WorkspaceStore expected-state check and write
  -> visible success, duplicate, permission, privacy, or recovery receipt
```

Failure must not silently substitute clipboard data, overwrite an external
edit, or allow later mutations to replace a buffered recovery.

### Panel presentation

```text
user/status/hotkey/pointer event
  -> FloatingPanelController samples engagement
  -> PanelPresentationMachine emits effects
  -> controller changes the same CuePanel
  -> pointer settle/retraction is rearmed from current physical state
```

`expandedFrame` is canonical saved geometry. A 22x88 rail and its hover bridge
are derived frames, never saved positions. Rail click may focus while remaining
anchored to the current edge; explicit programmatic show restores canonical
geometry. Display, Dock, and Stage Manager changes must repair the canonical
frame and any pending rail placement from the same screen snapshot.

## Proof ownership

- `Checks/CueCoreChecks/main.swift`: pure policy, codec, storage, selection, and
  geometry contracts.
- `Sources/Cue/IntegrationCheckRunner.swift`: `AppModel` plus real AppKit owner
  paths, including retained `NSPanel` behavior.
- `scripts/check.sh`: normal Debug build plus both deterministic suites.
- `swift build -Xswiftc -warnings-as-errors`: the separate compiler-warning
  release gate.
- `scripts/package_app.sh`: Release bundle construction, Info.plist validation,
  and signing.
- `docs/EXPERIMENTS.md`: physical keyboard, Accessibility, other-app,
  WindowServer, display, Dock, Stage Manager, and packaged-runtime checks that
  deterministic tests cannot honestly replace.

A green private helper is insufficient when the public owner path can diverge.
For panel work, drive the real `CuePanel` event callback. For storage work,
prove the complete package and recovery outcome. For capture work, prove that
every cancelled, denied, protected, or failed path persists zero content.

## Change discipline

Before editing, name one behavior invariant, its owner, the smallest native
change, and the public proof. Keep exactly one integration writer. Reviewers
remain read-only. Commit code, evidence, and documentation in rollback-sized
intent boundaries, then reconcile the owning Feature rather than maintaining a
parallel progress log here.

Borrowed implementation patterns and licenses are recorded in
`THIRD_PARTY_NOTICES.md`; consult it before copying more upstream code or
changing attribution.
