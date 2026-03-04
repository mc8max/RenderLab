# RenderLab

## Project Structure

```text
RenderLab/
├── App/
│   ├── RenderLabApp.swift
│   ├── Import/
│   │   └── OBJLoader.swift
│   ├── Scene/
│   │   ├── SceneObjectSnapshot.swift
│   │   ├── ScenePanelContracts.swift
│   │   └── SceneTransform.swift
│   ├── Renderer/
│   │   ├── Bridge/
│   │   │   └── CoreSceneBridge.swift
│   │   ├── Passes/
│   │   │   ├── AxisPass.swift
│   │   │   ├── ClearPass.swift
│   │   │   ├── GridPass.swift
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
├── Shaders/
│   └── BasicShaders.metal
├── Architecture.md
└── README.md
```

## Module Overview

- `App/Scene/`
  Shared scene domain and renderer/UI synchronization contracts.
- `App/Renderer/`
  Metal lifecycle, camera, frame context assembly, scene editing, and pass orchestration.
- `App/Renderer/Bridge/`
  Swift bridge wrapper for CoreCPP scene ownership and object access.
- `App/UI/Scene/`
  Scene sidebar model and view (selection, visibility, add-cube).
- `Core/`
  C/C++ engine-side math, camera, scene storage, and C bridge entry points.
- `Shaders/`
  Metal shader functions used by render passes.

See `Architecture.md` for data flow and boundary rules.
