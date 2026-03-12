# AGENTS.md

This file is a working guide for coding agents in this repository.

## 1) Project Mission
RenderLab is a macOS Metal playground for:
- Scene rendering and editing
- Interpolation Lab (keyframe interpolation + playback)
- Vertex Blending Lab (GPU linear blend skinning)
- Diagnostics and HUD-based runtime analysis

Current Vertex Blending scope is implemented through PR1-PR5.

## 2) Repository Map
- `App/Scene/`
  Shared scene domain types and UI/renderer contracts.
- `App/Renderer/`
  Renderer state, lifecycle, frame context, scene editing, interpolation/skinning orchestration.
- `App/Renderer/Passes/`
  Render passes (`MainPass`, `SkinningSkeletonPass`, guides, HUD).
- `App/UI/`
  SwiftUI and MTKView bridge.
- `App/UI/Scene/`
  Scene panel model + view.
- `Core/`
  C/C++ core math, scene, interpolation bridge.
- `Shaders/`
  Metal shader entry points (`BasicShaders.metal`).
- `Docs/`
  Design notes, issues, backlog, and feature docs.

## 3) Key Architecture Rules
- UI -> renderer commands must flow through `SceneCommandBridge`.
- Renderer -> UI state must flow through `RendererSceneSink` snapshots.
- Keep scene domain contracts in `App/Scene/` so UI and renderer share one source of truth.
- Do not couple renderer code directly to SwiftUI views/models.
- Keep rigid and skinned mesh paths separate by vertex layout (`positionColor` vs `skinnedPositionColorBone4`).

## 4) Build and Validation
From `RenderLab/RenderLab` directory:
- Build:
  - `xcodebuild -project ../RenderLab.xcodeproj -scheme RenderLab -configuration Debug -sdk macosx build`

Validation checklist for graphics changes:
- Build succeeds.
- Rigid path still renders correctly.
- Skinning ON/OFF toggles correctly on skinned objects.
- Skeleton overlay toggles and aligns with deformation.
- Debug modes render expected color output.
- Playback controls (play/pause/scrub/speed/loop) remain stable.

## 5) Vertex Blending Implementation Notes
Primary files:
- `App/Renderer/RenderAssets.swift`
- `App/Renderer/Renderer+InterpolationLab.swift`
- `App/Renderer/Passes/MainPass.swift`
- `App/Renderer/Passes/SkinningSkeletonPass.swift`
- `Shaders/BasicShaders.metal`
- `App/Renderer/RenderTypes.swift`
- `App/Scene/InterpolationLabTypes.swift`
- `App/UI/Scene/ScenePanelView.swift`
- `App/UI/Scene/ScenePanelModel.swift`
- `App/Scene/ScenePanelContracts.swift`
- `App/UI/MetalView.swift`

Important current behavior:
- Procedural skinned ribbon defaults to 96 segments, 16 bones, 4 influences per vertex.
- Runtime rig is a chain rig that aligns bone count with skinned mesh metadata.
- Bone palette uploads are dirty-driven (avoid unnecessary copies).
- Shader clamps indices, normalizes weights, and safely handles `boneCount == 0`.
- Skinned demo is rendered two-sided for inspection clarity.

## 6) Scene Bootstrap Expectations
- Default startup scene always includes a centered skinned ribbon demo object.
- OBJ mug loading is opt-in (`preferTeamUGOBJ`).
- Default fallback cube bootstrap is disabled.

If you change bootstrap behavior, update:
- `App/Renderer/BootstrapScene.swift`
- `App/Renderer/Renderer+Lifecycle.swift`
- `Docs/VertexBlending.md` (if skinning flow changes)

## 7) Performance Guardrails
Known risk area is main-thread scheduling pressure, not pure GPU cost.

When changing playback/sync code:
- Avoid high-frequency main-thread publishes.
- Keep snapshot publishing throttled by playback/visibility state.
- Preserve sink coalescing in `ScenePanelModel`.
- Avoid per-frame allocations in passes and palette upload paths.

Diagnostics references:
- `App/Renderer/Renderer+HUD.swift`
- `Docs/Issues/FrameRate.md`
- `Docs/HUD.md`

## 8) UI Change Guardrails
For Scene Panel or lab controls:
- Keep control state selection-aware (`isSelectedObjectSkinned` checks).
- Preserve object list height cap behavior (space for lab sections).
- Route all mutations through command bridge + local optimistic model update.

## 9) Shader/CPU Struct Sync Rule
If you modify shader uniforms/params:
- Update matching Swift structs and binding indices.
- Verify `MainPass` buffer bindings and layout offsets.
- Re-check all debug modes and fallback paths.

## 10) Documentation Expectations
When behavior changes, update relevant docs in the same change:
- `Docs/VertexBlending.md` for skinning/lab behavior
- `Docs/HUD.md` for diagnostics/HUD changes
- `Docs/Issues/*.md` for root-cause/perf investigations
- `Tasks/VertexBlendingLabPlan.md` when PR status/plan milestones shift
- For long-running or multi-step tasks, log and maintain the current task plan in the `Tasks/` directory.

## 11) Open Constraints / Future Work
- Public manipulator is still `Bone1 Z` only (chain propagation is internal).
- Imported skinned assets (for example glTF skin import) are not implemented.
- Advanced normal/tangent skinning workflows are not yet introduced.
- Scene snapshot rebuild cost can grow with scene size; keep future changes mindful of this.
