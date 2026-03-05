# RenderLab

## Project Structure

```text
RenderLab/
├── App/
│   ├── RenderLabApp.swift
│   ├── Import/
│   │   └── OBJLoader.swift
│   ├── Scene/
│   │   ├── InterpolationLabTypes.swift
│   │   ├── SceneObjectSnapshot.swift
│   │   ├── ScenePanelContracts.swift
│   │   └── SceneTransform.swift
│   ├── Renderer/
│   │   ├── Bridge/
│   │   │   ├── CoreInterpolationBridge.swift
│   │   │   └── CoreSceneBridge.swift
│   │   ├── Passes/
│   │   │   ├── AxisPass.swift
│   │   │   ├── ClearPass.swift
│   │   │   ├── GridPass.swift
│   │   │   ├── InterpolationGhostPass.swift
│   │   │   ├── MainPass.swift
│   │   │   ├── PassCommon.swift
│   │   │   └── SceneGuideConfig.swift
│   │   ├── BootstrapScene.swift
│   │   ├── RenderAssets.swift
│   │   ├── RenderPass.swift
│   │   ├── RenderSettings.swift
│   │   ├── RenderTypes.swift
│   │   ├── Renderer.swift
│   │   ├── Renderer+Camera.swift
│   │   ├── Renderer+FrameContext.swift
│   │   ├── Renderer+HUD.swift
│   │   ├── Renderer+InterpolationLab.swift
│   │   ├── Renderer+Lifecycle.swift
│   │   ├── Renderer+SceneEditing.swift
│   │   └── SceneTransformBridge.swift
│   └── UI/
│       ├── ContentView.swift
│       ├── HUDModel.swift
│       ├── HUDView.swift
│       ├── MetalView.swift
│       ├── OrbitMTKView.swift
│       └── Scene/
│           ├── ScenePanelModel.swift
│           └── ScenePanelView.swift
├── Assets.xcassets/
├── Core/
│   ├── CoreInterpolation.h
│   ├── CoreInterpolation.cpp
│   └── CoreInterpolationBridge.cpp
├── Shaders/
│   └── BasicShaders.metal
├── Architecture.md
└── README.md
```

## Module Overview

- `App/Scene/`
  Shared scene domain and renderer/UI synchronization contracts, including Interpolation Lab snapshot types.
- `App/Renderer/`
  Metal lifecycle, camera, frame context assembly, scene editing, interpolation orchestration, and pass orchestration.
- `App/Renderer/Bridge/`
  Swift wrappers for CoreCPP scene ownership plus Interpolation Lab C bridge calls.
- `App/UI/Scene/`
  Scene sidebar model and view (selection, visibility, add-cube, Interpolation Lab controls).
- `Core/`
  C/C++ engine-side math, camera, scene storage, Interpolation Lab compute, and C bridge entry points.
- `Shaders/`
  Metal shader functions used by main and ghost render passes.

## Interpolation Lab (v1)

Interpolation Lab is a built-in playground for blending between two keyframes (`A` and `B`) of the selected object.

- Keyframe tools:
  - Set `A`, Set `B`, Swap, Apply `A`, Apply `B`, Reset.
- Time + playback:
  - `t` slider (`0...1`), Play/Pause, speed (`0.25x`, `1x`, `2x`), loop modes (Clamp, Loop, Ping-Pong).
- Interpolation modes:
  - Position/Scale: Lerp, Smoothstep, Cubic.
  - Rotation: Euler Lerp, Quaternion Nlerp, Quaternion Slerp.
  - Shortest-path toggle for quaternion interpolation.
- Debug views:
  - Ghost `A` and Ghost `B` overlays rendered as transparent wireframe.
  - Numeric readout for interpolated TRS and distances to `A`/`B`.

### CoreCpp Ownership

Interpolation math and transform/uniform computation run in `Core/`:

- Playback advance (`t`, speed, loop/ping-pong behavior)
- TRS interpolation (including quaternion shortest-path handling)
- Ghost/object uniform generation

The Swift renderer/UI layer only orchestrates state, sends commands, and consumes Core-computed outputs.

### Bootstrap Defaults

At startup, the default object is seeded with FrameA/FrameB in Interpolation Lab:

- FrameA matches the initial object transform.
- FrameB is preconfigured with both translation and rotation offsets from FrameA.

See `Architecture.md` for data flow and boundary rules.
