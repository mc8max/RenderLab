# Morph Target Lab

## Overview
This document consolidates Morph Target Lab implementation from PR1 to PR5.

Implementation status:
- PR1: Morph domain wiring + procedural morph mesh + GPU morph route
- PR2: Multi-target blending + validation hardening
- PR3: Morph debug modes
- PR4: Playback controls + snapshot cadence tuning
- PR5: Performance hardening + bootstrap polish + composition hooks

## Runtime Model
Current morph deformation is GPU-side position blending:
- `p' = p_base + sum_i(w_i * delta_i)`

Current constraints:
- Target count is clamped to `MorphLabLimits.maxTargets` (`8`).
- Weights are clamped to `[0, 1]`.
- Morph path currently applies to `positionColor` meshes with registered morph delta buffers.

## Implemented Features

### 1) Domain and Command Wiring
- `MorphLabSnapshot` carries UI-facing state (enabled, playback, weights, debug).
- `SceneCommandBridge` exposes morph commands (enable, playback, target weights, debug, reset).
- `ScenePanelModel` supports local optimistic morph updates.
- `MetalView` forwards morph commands to `Renderer`.

### 2) Asset and Validation Path
- `RenderAssets.registerMorphed(...)` validates:
  - target count range
  - topology and packed delta count
  - finite and sane delta magnitudes
  - base vertex and index validity
- Procedural morph ribbon (`registerMorphRibbon`) provides multi-target demo geometry.

### 3) GPU Morph Pipeline
- `MainPass` routes morph-enabled objects to `vs_morph_main`.
- Morph vertex shader accumulates weighted deltas and supports debug color modes.
- Non-morph objects continue using rigid/skinning routes unchanged.

### 4) Debug Modes
- `none`
- `displacement` (magnitude of applied weighted delta)
- `selectedTargetDelta` (magnitude of selected target delta)
- `outlier` (threshold-based displacement highlighting)

### 5) Playback Controls
- Play/pause
- Timeline (`0...1`)
- Speed
- Loop on/off
- PR4 behavior animates target `0` from playback timeline.

### 6) PR5 Performance Hardening
- Morph weights now use a reusable GPU buffer (`weightParamsBuffer`) rather than per-draw weight array packing.
- Weight uploads are dirty-driven (`isWeightParamsDirty`) and only copied when values change.
- Frame path reuses the same morph weight buffer across frames.

### 7) PR5 Composition Hook
- Added `MorphSkinningCompositionMode` with:
  - `disabled`
  - `morphThenSkinning`
- `MainPass` includes explicit route hook checks for future morph+skinning composition while preserving current behavior.

### 8) PR5 Bootstrap Polish
- Added explicit bootstrap toggle for default morph demo object:
  - `BootstrapScene.enableDefaultMorphDemoObject`
- Added shared default morph object naming constant:
  - `BootstrapScene.morphDemoObjectName`

## Source Code Index

### Domain and UI/Renderer Contracts
- `App/Scene/InterpolationLabTypes.swift`
- `App/Scene/ScenePanelContracts.swift`
- `App/UI/MetalView.swift`
- `App/UI/Scene/ScenePanelModel.swift`
- `App/UI/Scene/ScenePanelView.swift`

### Renderer State and Logic
- `App/Renderer/Renderer.swift`
- `App/Renderer/Renderer+InterpolationLab.swift`
- `App/Renderer/Renderer+FrameContext.swift`
- `App/Renderer/Renderer+Lifecycle.swift`
- `App/Renderer/RenderTypes.swift`

### Assets, Pass, and Shader
- `App/Renderer/RenderAssets.swift`
- `App/Renderer/Passes/MainPass.swift`
- `Shaders/BasicShaders.metal`

### Bootstrap
- `App/Renderer/BootstrapScene.swift`
