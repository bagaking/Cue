#!/usr/bin/env bash
set -euo pipefail

CUE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CUE_ROOT"
mkdir -p .build/checks

swift build

swiftc \
  -swift-version 5 \
  -o .build/checks/CueCoreChecks \
  Sources/Cue/Models.swift \
  Sources/Cue/ContentHasher.swift \
  Sources/Cue/MarkdownWorkspaceCodec.swift \
  Sources/Cue/WorkspacePackageCodec.swift \
  Sources/Cue/WorkspaceSearchIndex.swift \
  Sources/Cue/WorkspaceStore.swift \
  Sources/Cue/ItemSelectionModel.swift \
  Sources/Cue/ModifierTapDetector.swift \
  Sources/Cue/CapturePolicy.swift \
  Checks/CueCoreChecks/main.swift

.build/checks/CueCoreChecks
.build/debug/Cue --integration-checks
