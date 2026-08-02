#!/usr/bin/env bash
set -euo pipefail

CUE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CUE_ROOT"
mkdir -p .build/checks

swift build

CUE_CORE_OBJECTS=(.build/debug/CueCore.build/*.swift.o)

swiftc \
  -swift-version 5 \
  -I .build/debug/Modules \
  -o .build/checks/CueCoreChecks \
  Sources/Cue/Models.swift \
  Sources/Cue/PanelPresentation.swift \
  Sources/Cue/SettingsStore.swift \
  Sources/Cue/MarkdownWorkspaceCodec.swift \
  Sources/Cue/WorkspaceSearchIndex.swift \
  Sources/Cue/WorkspaceLegacyImporter.swift \
  Sources/Cue/ItemSelectionModel.swift \
  Sources/Cue/ModifierTapDetector.swift \
  Sources/Cue/CapturePolicy.swift \
  Checks/CueCoreChecks/main.swift \
  "${CUE_CORE_OBJECTS[@]}"

.build/checks/CueCoreChecks
.build/debug/Cue --integration-checks
