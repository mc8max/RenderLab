# Vertex Blending (Skinning Lab)

## Overview
This document consolidates the implemented Vertex Blending Lab scope from **PR1 to PR5**.

Implementation status:
- PR1: Data wiring + procedural skinned mesh + GPU skinning ON/OFF
- PR2: Bind/inverse-bind correctness + validation checks
- PR3: Debug modes + skeleton overlay
- PR4: Playback controls + UI/UX polish
- PR5: Scaled bone count/influences + runtime hardening

## Core Skinning Model
The runtime uses Linear Blend Skinning (LBS):
- `p' = sum_i( w_i * (M_i * p) )`
- `M_i = GlobalPose_i * InverseBind_i`

Validation and safety guards:
- CPU vertex validation enforces non-negative weights, near-unit weight sums, and in-range indices.
- GPU skinning normalizes weights again and clamps indices to valid palette range.
- `boneCount == 0` is handled safely in shader by falling back to rigid transform.

## Implemented Features

### 1) UI + Command/Data Wiring
- Added Skinning Lab snapshot model (`SkinningLabSnapshot`) and debug mode enum (`SkinningDebugMode`).
- Added command bridge methods for skinning controls.
- Added local optimistic UI state updates and renderer snapshot sync.
- Added coalesced sink-update flushing on main queue to reduce UI churn.

### 2) Skinned Mesh Asset Path
- Added dedicated skinned vertex layout: `position/color/boneIndices/boneWeights`.
- Added skinned mesh registration path with layout metadata.
- Added procedural skinned ribbon demo mesh.
PR5 scaling updates:
- Ribbon defaults increased to `segmentCount = 96`.
- Default skinning rig target increased to `boneCount = 16`.
- Vertex influences upgraded to nearest **4 bones** with normalized weights.

### 3) GPU Skinning Render Path
- Added `vs_skin_main` and skinned vertex descriptor path.
- Main pass routes by mesh layout:
- `positionColor` meshes use rigid pipeline.
- `skinnedPositionColorBone4` meshes use skinned pipeline when Skinning is enabled.
- skinned meshes fall back to rigid pipeline when Skinning is disabled.
- Skinned demo is rendered two-sided (`cullMode = none`) for inspection stability.

### 4) Rig, Palette, and Playback
- Added bind pose, inverse bind, and per-frame final palette generation.
- Added skinning playback controls: play/pause, clip time, speed, loop.
- Added manual `Bone1 Z (deg)` control.
PR5 rig hardening:
- Replaced fixed 2-bone demo assumption with scalable chain rig generation.
- Auto-aligns runtime rig bone count with active skinned mesh bone count.
- Bone1 control now propagates down the chain with decayed influence.
- Palette upload is dirty-driven to avoid unnecessary per-frame CPU->GPU buffer copies.

### 5) Debug Views + Skeleton Overlay
Added debug modes:
- `None`
- `Dominant Bone`
- `Weight Heatmap` (selected bone)
- `Weight Sum Check`
- `Index Validity`
- Added `SkinningSkeletonPass` overlay (joints + bone lines) with toggle.

### 6) Runtime Stability and Performance Hardening
- Skinning snapshots are throttled by playback state (idle vs playing publish intervals).
- UI sync can be suspended during playback and while app/window state is inactive/occluded.
- Playback state integrates App Nap suppression during active playback.
- Scene sink updates are coalesced before main-thread flush to reduce UI churn.
- Palette buffer writes are skipped when data is unchanged.

### 7) Scene Bootstrap and Defaults
- Default bootstrap scene now always adds a centered skinned ribbon demo object.
- Mug/OBJ loading is non-default (opt-in via `preferTeamUGOBJ`).
- Fallback default cube loading is disabled in bootstrap path.

### 8) Scene Panel UX Updates
- Skinning Lab panel includes selection-aware enable/disable states.
- Object selection list height was reduced/capped to reserve more vertical space for lab controls.

## End-to-End Data Flow
1. `ScenePanelView` issues skinning commands through `SceneCommandBridge`.
2. `MetalView` forwards commands to `Renderer` methods.
3. `Renderer` updates skinning state, pose, and palette buffer.
4. `Renderer` publishes `SkinningLabSnapshot` back to `ScenePanelModel`.
5. `Renderer+FrameContext` emits `SkinningLabFrameState` for render passes.
6. `MainPass` consumes skinning frame data for skinned draw calls.
7. `SkinningSkeletonPass` consumes the same frame data for skeleton overlay.

## Source Code Index

### Domain Types and Commands
- `App/Scene/InterpolationLabTypes.swift`
- `App/Scene/ScenePanelContracts.swift`
- `App/UI/MetalView.swift`
- `App/UI/Scene/ScenePanelModel.swift`
- `App/UI/Scene/ScenePanelView.swift`

### Asset and Vertex Layout
- `App/Renderer/RenderAssets.swift`
- `App/Renderer/Passes/PassCommon.swift`

### Renderer State and Frame Wiring
- `App/Renderer/Renderer.swift`
- `App/Renderer/Renderer+Camera.swift`
- `App/Renderer/Renderer+FrameContext.swift`
- `App/Renderer/Renderer+InterpolationLab.swift`
- `App/Renderer/Renderer+Lifecycle.swift`
- `App/Renderer/Renderer+SceneEditing.swift`
- `App/Renderer/RenderTypes.swift`

### Render Passes and Shader
- `App/Renderer/Passes/MainPass.swift`
- `App/Renderer/Passes/SkinningSkeletonPass.swift`
- `Shaders/BasicShaders.metal`

### Bootstrap
- `App/Renderer/BootstrapScene.swift`

## Current Constraints
- The public manipulator is still a single `Bone1 Z` control (chain propagation is internal).
- Demo mesh is procedural ribbon-based; imported skinned formats (for example glTF skin import) are not yet part of this scope.
- Skinning path currently focuses on position deformation and debug visualization; advanced normal/tangent skinning workflows are not yet introduced.
