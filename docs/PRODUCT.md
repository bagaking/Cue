# Cue product contract

## Protected outcome

Keep the next thought without leaving the work in front of you. Capture should take less attention than switching to a note app, and recovery should not create a second inbox that needs constant grooming.

## Core object

Every selected fragment and typed prompt is a `WorkItem` with one lifecycle: queued, completed, archived. Source metadata may differ; commands and storage do not.

## Default commands

| Scope | Command | Result |
|---|---|---|
| Global | double Shift on the same physical key | Capture only the readable foreground selection |
| Menu bar | Show Cue | Open the sidecar and preserve a compact edge position |
| Sidecar | ↑ / ↓ | Move visible focus |
| Sidecar | ⇧↑ / ⇧↓ | Extend selection |
| Sidecar | ⌘C | Copy focused item |
| Sidecar | ⌘⇧C | Copy selection as an ordered Markdown list |
| Sidecar | X | Toggle explicit completion |
| Sidecar | ⌘F | Focus search |
| Sidecar | ⌘Z | Undo the last reversible queue mutation |
| Section title | click | Make that section the explicit capture target |
| Composer | ⌘↩ | Queue a prompt |
| Composer | ⇧↩ | Insert a newline |

## Trust boundary

- Note content never leaves the Mac.
- No telemetry or crash upload is implemented.
- Global capture reads the current accessibility selection only after double Shift or the explicit menu command.
- Password/secure fields and user-denylisted apps are rejected before selected text is persisted.
- Source app name is on by default. Window titles are off by default. URLs are never inferred from clipboard content.
- If selected text is unavailable, Cue says so and offers the composer; it never substitutes clipboard history.

## Storage and recovery

- `.cue` workspace packages remain editable outside Cue; each WorkItem body lives in its own Markdown document.
- Cue fingerprints package files and rejects a write when it detects a change before the schema-2 precondition check. That check is not coordinated with the later multi-file write, so concurrent writers can still race; schema 3 owns complete snapshot/CAS protection.
- A failed write keeps the exact intended document state plus a readable Markdown recovery export; later mutations are paused so they cannot replace it.
- Recovery offers exact Copy, a complete conflict-copy package, and a previewed three-way merge. Only non-overlapping object changes merge automatically; same-object conflicts stop.
- A timestamped package backup is made before changing an existing workspace; at least the latest ten are retained.
- Tombstones make physical deletion representable outside the app. The current timestamp form has not passed dual-Mac conflict qualification and does not by itself make Cue a reliable sync product. The local search index is rebuildable and never authoritative.
- Merge archives originals with provenance and can be undone as one snapshot.

## Responsive window contract

- The supported resize range is 352×500 through 560×900 points.
- Below 560 points tall, Cue collapses Search behind an explicit button and reduces composer chrome while keeping queue and input reachable.
- At compact width, Archive and Settings move into one More menu instead of truncating the workspace title.
- Onboarding scrolls at the minimum size; accepting a frame is not considered support if content is clipped.

## V1 exclusions

Passive capture, cloud sync, teams, automatic AI rewriting, arbitrary-app paste/Send injection, calendar/reminder features, and background clipboard history are separate product categories and are not implemented.
