fix(panel): stabilize edge hover across frame animations

## Context
- Why: Programmatic NSPanel movement could manufacture hover loops or discard a real rail entry, leaving Cue jittering or unreachable.

## Key Deltas
- panel owner: tracking callbacks trusted AppKit events during programmatic frame changes -> controller gates events with event time, sampled Quartz position, and animation-token baselines; why: prevent window motion from manufacturing hover while preserving one real animation-period rail entry. Key refs: Sources/Cue/FloatingPanelController.swift:590, Sources/Cue/PanelPresentation.swift:136
- hover geometry: canonical expanded geometry stopped eight points short of the right rail -> hover preview derives a transient rail-contiguous frame without mutating expandedFrame; why: keep the cursor path continuous while preserving persisted geometry. Key refs: Sources/Cue/FloatingPanelController.swift:391, Sources/Cue/PanelPresentation.swift:237

## Validation
- pass: swift build -Xswiftc -warnings-as-errors
- pass: scripts/check.sh (Core 89/89; AppKit Integration 47/47)
- pass: independent tracking/hysteresis and frozen-diff reviews


[[BAGAKIT]]
- GitMessageCraft: Protocol=bagakit.git-message-craft/v1

Feature-ID: f-223j2ezq3
Task-ID: T-002
Gate-Result: pass
Task-Status: done
