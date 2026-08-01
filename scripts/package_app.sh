#!/usr/bin/env bash
set -euo pipefail

CUE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CUE_ROOT"

swift build -c release
swift scripts/make_icon.swift Resources/AppIcon.icns

CUE_APP="$CUE_ROOT/dist/Cue.app"
rm -rf "$CUE_APP"
mkdir -p "$CUE_APP/Contents/MacOS" "$CUE_APP/Contents/Resources"

cp -f "$CUE_ROOT/.build/release/Cue" "$CUE_APP/Contents/MacOS/Cue"
cp -f "$CUE_ROOT/Resources/Info.plist" "$CUE_APP/Contents/Info.plist"
cp -f "$CUE_ROOT/Resources/AppIcon.icns" "$CUE_APP/Contents/Resources/AppIcon.icns"
cp -f "$CUE_ROOT/THIRD_PARTY_NOTICES.md" "$CUE_APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp -f "$CUE_ROOT/docs/PRODUCT.md" "$CUE_APP/Contents/Resources/PRODUCT.md"
cp -f "$CUE_ROOT/docs/EXPERIMENTS.md" "$CUE_APP/Contents/Resources/EXPERIMENTS.md"

codesign --force --deep --sign - "$CUE_APP"
codesign --verify --deep --strict "$CUE_APP"
plutil -lint "$CUE_APP/Contents/Info.plist"

echo "$CUE_APP"
