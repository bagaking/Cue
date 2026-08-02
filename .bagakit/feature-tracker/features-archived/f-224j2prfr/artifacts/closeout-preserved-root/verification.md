# Verification Evidence

## Automated Checks
- `swift build -Xswiftc -warnings-as-errors`: passed at commit `7f7e519debde54314b8e2c730c0fc44e5b79acd6`.
- `.build/debug/Cue --integration-checks`: 57 passed, 0 failed, including public show, poisoned hidden toggle, terminal pointer resampling, rail click anchoring and hover reveal.
- `sh scripts/check.sh`: 92 core and 57 integration checks passed.
- `sh scripts/package_app.sh`: Release build, ad-hoc signing and Info.plist validation passed.
- `codesign --verify --deep --strict --verbose=2 dist/Cue.app`: valid on disk and satisfies its designated requirement.

## Manual Checks
- Previous package reproduced a user-visible rail-click jump to the old canonical left-side frame.
- The repaired package keeps rail click and hover-promotion expansion connected to the clicked edge; only global explicit reveal restores canonical geometry.
- The exact executable SHA-256 is `776e91dd92cba05402030ec167d7a6f9416b987091f831c5827f031131103b8a`.
- The packaged executable is live under supervised session `98710`; an empty five-second process poll returned a live session with no crash output.
- `origin/main` advanced from `0ac58e6` through `5407acf` to `7f7e519`.

## Residual Risks
- Physical multi-display disconnect, side-Dock/Stage Manager layouts and a long external drag still require hardware/user qualification; deterministic geometry and engagement gates pass.
