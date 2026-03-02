# RenderLab

## Project Structure

```text
RenderLab/
├── App/
│   ├── RenderLabApp.swift
│   ├── Renderer/
│   │   ├── BootstrapScene.swift
│   │   ├── CoreScene.swift
│   │   ├── Passes/
│   │   │   ├── AxisPass.swift
│   │   │   ├── ClearPass.swift
│   │   │   ├── GridPass.swift
│   │   │   ├── MainPass.swift
│   │   │   ├── PassCommon.swift
│   │   │   └── SceneGuideConfig.swift
│   │   ├── RenderAssets.swift
│   │   ├── RenderPass.swift
│   │   ├── RenderSettings.swift
│   │   ├── RenderTypes.swift
│   │   ├── Renderer.swift
│   │   └── SceneTransformBridge.swift
│   └── UI/
│       ├── ContentView.swift
│       ├── HUDModel.swift
│       ├── HUDView.swift
│       ├── MetalView.swift
│       └── OrbitMTKView.swift
├── Assets.xcassets/
│   ├── AccentColor.colorset/
│   ├── AppIcon.appiconset/
│   └── Contents.json
├── Core/
│   ├── CoreBridge.cpp
│   ├── CoreBridge.h
│   ├── CoreCamera.cpp
│   ├── CoreCamera.h
│   ├── CoreMath.hpp
│   ├── CoreMeshBridge.cpp
│   ├── CoreScene.cpp
│   ├── CoreScene.h
│   ├── CoreSceneBridge.cpp
│   ├── CoreUniformBridge.cpp
│   └── RenderLab-Bridging-Header.h
├── Shaders/
│   └── BasicShaders.metal
└── Readme.md
```

## Module Overview

- `App/`
  SwiftUI app layer and Metal renderer orchestration.
- `App/Renderer/`
  Frame lifecycle, settings, render context, and scene/asset wrappers.
- `App/Renderer/Passes/`
  Render pass implementations (`Clear`, `Main`, `Grid`, `Axis`) plus shared helpers/config.
- `App/UI/`
  SwiftUI views and MTKView input bridge.
- `Core/`
  C/C++ engine-side math, camera, scene data, and bridge entrypoints exposed to Swift.
- `Shaders/`
  Metal shader functions used by render passes.
