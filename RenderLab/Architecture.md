# Architecture

## Layers

1. `Core/` (C/C++)
   Engine-side math, camera, scene storage, and bridge exports.
2. `App/Renderer/Bridge/`
   Swift wrapper around `CoreSceneHandle` and bridge calls.
3. `App/Renderer/`
   Metal lifecycle, pass orchestration, camera updates, and scene-edit commands.
4. `App/Scene/`
   Shared scene contracts (`RendererSceneSink`, `SceneCommandBridge`) and scene domain snapshots.
5. `App/UI/`
   SwiftUI composition and platform view bridging.
6. `App/UI/Scene/`
   Scene sidebar state/view.

## Data Flow

1. UI command flow:
   `ScenePanelView -> SceneCommandBridge -> MetalView.Coordinator -> Renderer`.
2. Scene snapshot flow:
   `Renderer -> RendererSceneSink (ScenePanelModel) -> ScenePanelView`.
3. Render loop flow:
   `Renderer+Lifecycle -> RenderContext -> Passes -> Shaders`.

## Boundary Rules

1. `Renderer` does not depend on concrete UI models; it only emits `RendererSceneSink` snapshots.
2. UI state (`ScenePanelModel`) does not call renderer directly; commands route through `SceneCommandBridge`.
3. Core bridge wrappers (`CoreScene`) are isolated under `App/Renderer/Bridge/`.
4. Scene domain snapshots and contracts stay in `App/Scene/` so both renderer and UI can share them.
