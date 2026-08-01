# Cue experiment guide

Use the packaged Release app for every product experiment. Debug builds and
offscreen previews are useful engineering checks, but they do not prove real
focus, menu-bar, Accessibility, pasteboard, or responder behavior.

## Prepare

Requirements:

- macOS 14 or newer
- Apple Swift toolchain 5.10 or newer
- Accessibility permission only for the selected-text experiment

Build, check, and package the exact app under test:

```bash
cd /Users/bytedance/proj/priv/bagaking/Cue
sh scripts/check.sh
sh scripts/package_app.sh
dist/Cue.app/Contents/MacOS/Cue --show
```

Quit any already-running Cue instance from its menu-bar menu before using a
command-line QA entry point. This prevents two Cue processes from competing for
the same global shortcuts and workspace package.

Create a fresh workspace from Cue's workspace menu if you want an isolated
trial. This avoids deleting or resetting existing Cue settings and data.

## Five-minute smoke test

### 1. Typed capture without Accessibility

1. In Cue, enter two lines in the composer: `Smoke test` and `second line`.
2. Press `Command-Return`.
3. Confirm one queued card appears and the composer clears.
4. Quit and relaunch Cue with `--show`; confirm the card is still present.

Pass: multiline content is exact, no Accessibility permission is required, and
the `.cue/items/YYYY/MM/` tree contains one readable Markdown document for the item.

### 2. Exact selected-text capture

1. Open TextEdit and type `keep only this fragment please`.
2. Select only `this fragment`.
3. Run:

   ```bash
   /Users/bytedance/proj/priv/bagaking/Cue/dist/Cue.app/Contents/MacOS/Cue --capture-selection
   ```

4. Return focus to TextEdit before the two-second countdown ends.
5. Open Cue and inspect the new card.

Pass: the body is exactly `this fragment`, source app is TextEdit, Cue does not
capture the surrounding words or substitute clipboard content, and TextEdit
keeps focus during capture. If macOS has not granted Accessibility access, Cue
must show an explicit permission result while typed capture remains usable.

### 3. Ordered batch copy

1. Click the first card and use `Shift-Down` to select two cards.
2. Choose **Copy list** or press `Command-Shift-C`.
3. Paste into TextEdit.

Pass: card order matches the Cue list and multiline continuation lines are
indented by two spaces:

```markdown
- Smoke test
  second line
- this fragment
```

### 4. Lifecycle and recovery

1. Complete a card and wait about 750 ms.
2. Confirm it moves into **Recently Completed**.
3. Archive it, open Archive, then restore it.
4. Select two cards, open **Merge**, switch between Paragraphs and Bulleted
   list, confirm, then press `Command-Z`.

Pass: completion movement is delayed rather than abrupt; Archive is
recoverable; Merge archives both originals with one replacement; Undo restores
both originals and removes the merged item as one operation.

### 5. Search and routing

1. Search a unique word in the active queue, then search the same word in
   Archive.
2. Create a section, click its title to make it the capture target, and add a
   prompt.
3. Create a second workspace. In Settings > Workspaces, add a confirmed mapping
   from `com.apple.TextEdit` and an optional title phrase to that workspace.
4. Capture a selection from the matching TextEdit window.

Pass: active and Archive search scopes do not leak into each other; the new
prompt lands in the explicit section; only a confirmed matching mapping changes
workspace; Cue never invents a mapping.

## Copper-versus-Cue comparison

Use the same Mac, source text, target AI app, and five tasks in each product.
Alternate which product goes first to reduce learning bias. Run each task three
times and use the median.

| Task | Measure | Cue success bar |
|---|---|---|
| Capture one exact selection | selection-to-receipt time; foreground focus changed; character accuracy | receipt within 300 ms after command on a warm run; no focus theft; exact text |
| Queue a multiline prompt | keystrokes; formatting errors; permission dependency | one commit command; exact Markdown; works without Accessibility |
| Dispatch two items | time to paste-ready text; ordering/indent errors | one batch action; stable visual order; valid Markdown list |
| Close and recover work | time for complete, Archive, restore and Merge Undo; unrecoverable actions | all four paths recover without data loss |
| Survive an external edit | silent overwrite; recovery clarity; external bytes preserved | no silent overwrite; Reload/Save Copy/safe Merge offered; external bytes remain intact |

Record both numbers and observations. A product wins a task only if it is no
worse on correctness and recovery; a speed improvement does not compensate for
wrong selection, focus theft, silent overwrite, or unrecoverable loss.

Suggested result table:

| Product | Task | Median time | Errors | Focus preserved | Recoverable | Notes |
|---|---|---:|---:|---|---|---|
| Cue | Exact selection |  |  |  |  |  |
| Reference | Exact selection |  |  |  |  |  |

## Trust-boundary probes

Run these only with disposable text:

- Put unrelated text on the clipboard, make no readable selection, then invoke
  capture. Cue must not save the clipboard text.
- Attempt capture from a secure password field. Cue must persist zero content.
- Add an app bundle identifier to the denylist and capture from that app. Cue
  must persist zero content.
- Edit one item Markdown document inside the `.cue` package while Cue is open, then mutate a Cue
  item. Cue must stop the write and offer recovery instead of overwriting.
- Resize the panel to 352×500 points. Search should collapse into the header,
  Archive/Settings should remain available from More, the composer should stay
  usable, and onboarding should scroll instead of clipping.

## Physical input checks

These three checks require a human action because app-targeted automation does
not prove a process-wide shortcut or a real status-bar click:

- With text selected in a foreground app, tap and release the same physical
  Shift key twice. Cue should capture once. Typing a key between taps, holding
  another modifier, or using opposite Shift keys must not capture.
- Press the configured global show/hide and composer chords while another app
  owns focus. Cue should respond without the foreground app receiving stray
  characters.
- Left-click the Cue menu-bar icon to toggle the sidecar; right-click it to open
  the command/privacy menu. Confirm **Quit Cue** exits the process cleanly.

## Edge retract and Panel Pin probes

Use the packaged app and keep a text editor visible beside it. These are real
window-server probes; deterministic checks cover the state and geometry policy,
but cannot prove focus, Dock, Stage Manager, or physical display behavior.

1. Turn **Keep Cue panel open** off in the header. Click the editor, move away
   from Cue, and wait about one second. Cue should become a visible 22×88 handle
   on a horizontal screen edge. Hover the handle: Cue should expand without the
   editor losing focus or its selection changing. Move away again and confirm
   the short exit delay is long enough to cross any edge inset without flicker.
2. Type an unfinished composer draft, then click the editor and let Cue retract.
   Hover or click the handle. The draft, list selection, and scroll position must
   survive; a hover reveal must not place a caret or steal keyboard input.
   While the composer caret is actively editing, moving the pointer away must
   not retract Cue. Activate Finder without changing Cue's apparent key-window
   styling; editing protection should end and idle Cue should retract normally.
3. Resize expanded Cue to 352×500, then to 560×900. Retract and reveal after
   each size. The exact expanded size should return, content must not clip, and
   the compact header must keep its Panel Pin control visible.
4. Toggle Panel Pin on: Cue must remain expanded after leaving it. Toggle it off:
   Cue must not collapse immediately; it should retract only after a later safe
   disengagement. Separately verify **Pin item** changes queue ordering only and
   **Keep Cue above other windows** changes window level only.
5. Press Escape, use the global show/hide chord, and click the menu-bar item while
   Cue is expanded and while it is a rail. Each route should have one stable
   result: Escape hides; status/hotkey explicitly expands a rail; Composer opens
   expanded and focused. Rapidly repeat retract/reveal 20 times and look for
   frame drift, stuck transparency, stale animation, or an unreachable handle.
6. Quit and relaunch with `--show`. Cue should restore only the last expanded
   position and size—not a 22×88 rail frame—and `--show` should explicitly open
   it. Without clicking Cue or another window, leave the pointer outside: the
   explicit reveal should remain usable for the bounded delay and then retract,
   even if AppKit still reports the nonactivating panel as key. Turn Reduce
   Motion on and repeat; frames should change immediately with the same state semantics.
7. With Dock or Stage Manager on each side, verify Cue prefers the unobstructed
   horizontal edge. Enter a full-screen Space and verify the handle remains
   reachable without moving Cue to another Space.
8. On two displays, test negative-origin, side-by-side and vertically stacked
   arrangements. Place most of Cue on each display in turn, retract it, then
   disconnect that display while expanded and while retracted. Cue must repair
   to the remaining visible frame, choose a reachable rail, and never persist or
   expose a full panel body across a shared seam.

Record unavailable display, Dock, Stage Manager, or full-screen configurations
as untested rather than treating deterministic geometry checks as hardware proof.

## Evidence to keep

For a reviewable experiment, retain:

- macOS version and Mac model
- Cue executable SHA-256 (`shasum -a 256 dist/Cue.app/Contents/MacOS/Cue`)
- the five-task result table
- pasted batch-copy output
- the workspace package manifest and edited item Markdown before and after recovery probes
- screen recording or timestamps for capture latency and focus preservation
