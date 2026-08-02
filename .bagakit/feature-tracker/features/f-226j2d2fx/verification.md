# Verification Evidence

## Automated Checks
- `swift build -Xswiftc -warnings-as-errors`: pass on the intended five-file UI/link diff.
- Independent review: two edge-affordance reviewers and one link/security reviewer accepted the owner contract and bounded diff with no blocking finding.
- `git diff --check`: pass before delivery staging.
- Preview rendering, integration checks, and the full deterministic suite were not rerun for this delivery. Their current execution reaches the unrelated, paused T-006 `WorkspaceStore` create path, so they are not claimed as evidence for T-001.

## Manual Checks
- Edge rail:
  - Left and right edges read as an attached 18-point tongue inside the unchanged 22×88 hit area.
  - The canonical Cue app icon remains visible; the count is secondary; there is no chevron, full border, or settled shadow.
  - Hover and click reveal the panel, and the expanded shadow returns.
  - Repeat in light mode, dark mode, and Reduce Transparency.
- Note links:
  - Try bare `https://`, angle-bracketed `<https://>`, and labeled `[label](https://)` links.
  - Command-click opens each supported web link exactly once.
  - Ordinary click selects and double-click edits; Command-click does not also select or edit.
  - `file`, custom, `javascript`, and hostless URLs do not open.
- VoiceOver:
  - The rail exposes one **Reveal Cue** button with the count as its value.
  - The icon and count do not appear as duplicate accessible children.

## Residual Risks
- Manual inspection is pending for the exact packaged commit.
- No preview, integration, full-suite, or cross-display runtime result is claimed in this delivery record.
