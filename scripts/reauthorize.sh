#!/usr/bin/env bash
set -euo pipefail

# Repairs the "Selection access is off, but the system toggle is on" mismatch.
#
# Cue's ad-hoc designated requirement is CDHash-bound, so a changed build may no
# longer satisfy the Accessibility decision recorded for an earlier build. The
# bundle identifier selects that stale TCC entry for reset; it does not stabilize
# authorization across builds. Resetting never grants access by itself.

CUE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CUE_APP="$CUE_ROOT/dist/Cue.app"
CUE_EXECUTABLE="$CUE_APP/Contents/MacOS/Cue"
INFO_PLIST="$CUE_APP/Contents/Info.plist"

usage() {
  cat <<'EOF'
Usage: scripts/reauthorize.sh

Reset Cue's stale Accessibility decision, relaunch the packaged app, and let
the user grant access again from Cue Settings. Cue must not be running.
EOF
}

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 64
fi

case "${1:-}" in
  "") ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

if [[ ! -x "$CUE_EXECUTABLE" || ! -f "$INFO_PLIST" ]]; then
  echo "No app at $CUE_APP — run scripts/package_app.sh first." >&2
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
if [[ -z "$BUNDLE_ID" ]]; then
  echo "Cue's packaged Info.plist has no CFBundleIdentifier." >&2
  exit 1
fi

cue_is_running=false
if ! process_rows="$(ps -axo pid=,comm=)"; then
  echo "Unable to verify whether the packaged Cue app is running." >&2
  exit 1
fi

while read -r _ executable_path; do
  if [[ "$executable_path" == "$CUE_EXECUTABLE" ]]; then
    cue_is_running=true
    break
  fi
done <<<"$process_rows"

if [[ "$cue_is_running" == true ]]; then
  echo "Quit the packaged Cue app before resetting Accessibility." >&2
  exit 1
fi

echo "Resetting Accessibility grant for $BUNDLE_ID..."
tccutil reset Accessibility "$BUNDLE_ID"

echo "Relaunching Cue..."
open "$CUE_APP"

cat <<EOF

Reset complete. In Cue Settings, click "Enable…" and approve this build in
System Settings. Until that explicit approval succeeds, selection capture stays off.
EOF
