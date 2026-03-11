# Vertex Blending (Skinning Lab)

## Overview
This document summarizes the implemented scope for Vertex Blending Lab **PR1**.

PR1 goal:
- Data wiring for a dedicated Skinning Lab flow.
- Procedural skinned demo mesh.
- GPU skinning path with runtime ON/OFF comparison.

## PR1 Delivered Features

### 1. Skinning Lab UI and Command Wiring
- Added a `Skinning Lab` section in the Scene panel.
- Added controls:
  - `Skinning Enabled` toggle
  - `Bone1 Z (deg)` slider
  - `Bone Count` display
- Added renderer command bridge methods for skinning controls.
- Added renderer-to-UI snapshot publish path for skinning state.

Source code locations:
- `App/UI/Scene/ScenePanelView.swift`
- `App/UI/Scene/ScenePanelModel.swift`
- `App/Scene/ScenePanelContracts.swift`
- `App/Scene/InterpolationLabTypes.swift`
- `App/UI/MetalView.swift`
- `App/Renderer/Renderer+InterpolationLab.swift`
- `App/Renderer/Renderer+SceneEditing.swift`
- `App/Renderer/Renderer.swift`

### 2. Skinned Mesh Asset Path
- Added a separate skinned vertex layout (`position/color/boneIndices/boneWeights`).
- Added procedural skinned ribbon generation (2-bone influences).
- Added mesh metadata to distinguish rigid vs skinned vertex layout.

Source code locations:
- `App/Renderer/RenderAssets.swift`
- `App/Renderer/Passes/PassCommon.swift`

### 3. GPU Skinning in Vertex Shader
- Added `vs_skin_main` path:
  - Uses linear blend skinning on GPU.
  - Driven by a bone matrix palette.
- Main pass now chooses pipeline by mesh layout:
  - Rigid meshes -> rigid pipeline.
  - Skinned meshes -> skinned pipeline when skinning enabled.
  - Skinned meshes -> rigid fallback pipeline when skinning disabled.

Source code locations:
- `Shaders/BasicShaders.metal`
- `App/Renderer/Passes/MainPass.swift`
- `App/Renderer/RenderTypes.swift`
- `App/Renderer/Renderer+FrameContext.swift`
- `App/Renderer/Renderer+Camera.swift`
- `App/Renderer/Renderer+InterpolationLab.swift`

### 4. Bootstrap Behavior (Current Default)
- Mug/OBJ loading is non-default (opt-in only).
- Fallback cube loading is disabled in default bootstrap.
- Default skinned demo object (`Skinned Ribbon`) is spawned at scene center.

Source code locations:
- `App/Renderer/BootstrapScene.swift`
- `App/Renderer/Renderer+Lifecycle.swift`

## Improvements Added After PR1 Review

### High-severity safety improvements
- Added shader-side safety for palette access:
  - `boneCount` is passed from CPU to shader.
  - Bone indices are clamped to valid range.
  - Handles `boneCount == 0` safely.
- Added weight safety in shader:
  - Weights are normalized before skinning.
  - Degenerate weight sums fall back to `(1, 0, 0, 0)`.

Source code locations:
- `Shaders/BasicShaders.metal`
- `App/Renderer/Passes/MainPass.swift`
- `App/Renderer/RenderTypes.swift`

### Medium-severity rendering/scalability improvements
- Skinned demo rendering is now two-sided (no culling) for clearer lab inspection.
- Replaced per-draw temporary bone-matrix byte uploads with a persistent `MTLBuffer` palette path.

Source code locations:
- `App/Renderer/Passes/MainPass.swift`
- `App/Renderer/Renderer+InterpolationLab.swift`
- `App/Renderer/RenderTypes.swift`

## Data Flow
1. `ScenePanelView` issues skinning commands through `SceneCommandBridge`.
2. `MetalView.Coordinator` forwards commands to `Renderer`.
3. `Renderer` updates skinning state and palette buffer.
4. `Renderer` publishes `SkinningLabSnapshot` to `ScenePanelModel`.
5. `MainPass` consumes frame skinning state and renders with the appropriate pipeline.

## Current Scope Limits (Expected for PR1)
- Demo rig only (2 bones).
- Control is limited to Bone1 Z rotation.
- No bind-pose/inverse-bind correctness layer yet.
- No skeleton overlay yet.
- No advanced skinning debug modes yet (dominant bone, weight heatmap, sum/index checks visualization).

## Next Steps (PR2+)
- Add bind pose + inverse bind matrices and final palette correctness.
- Add explicit debug visual modes for weights/indices validity.
- Add skeleton overlay rendering.
- Extend animation controls and clip playback/blending.
