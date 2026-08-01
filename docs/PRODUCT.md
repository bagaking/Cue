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

- Markdown workspace files remain editable outside Cue.
- Cue fingerprints the loaded file and refuses silent last-write-wins behavior.
- A failed write keeps the exact intended Markdown snapshot in a recovery buffer; later mutations are paused so they cannot replace it.
- Recovery offers exact Copy/Save Copy plus a previewed three-way merge. Only non-overlapping object changes merge automatically; external prose remains authoritative and same-object conflicts stop.
- A timestamped backup is made before replacing an existing file; at least the latest ten are retained.
- Merge archives originals with provenance and can be undone as one snapshot.

## V1 exclusions

Passive capture, cloud sync, teams, automatic AI rewriting, arbitrary-app paste/Send injection, calendar/reminder features, and background clipboard history are separate product categories and are not implemented.
