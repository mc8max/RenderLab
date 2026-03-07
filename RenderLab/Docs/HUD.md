# HUD Component

## Overview
The HUD is a renderer-owned screen overlay that displays real-time performance and runtime diagnostics.
It is rendered inside the Metal frame pipeline (not SwiftUI), and updates independently from scene rendering.

## Core Features
- In-frame overlay rendering through `HUDOverlayPass`.
- Text panel with level-based content:
  - Basic: FPS, CPU ms, GPU ms
  - Verbose: basic metrics + frame time, mode, and detailed diagnostics lines
- Semi-transparent rounded background with monospaced diagnostics text.
- 3-level HUD mode support: `off`, `basic`, `verbose`.
- Automatic suppression when the app/window is in a background/occluded state.
- Rolling-window metrics for smoother readings.
- Optional diagnostics log dump to console (separate 30s dump window).

## Rendering Architecture
- The HUD pass is appended at the end of the render pass list.
- The pass builds a CPU-side RGBA texture from text lines (`AppKit` text draw into `CGContext`).
- Texture upload reuses ping-pong textures when dimensions match, and only reallocates on size change.
- A fullscreen-space quad section (top-left anchored) samples that texture with alpha blending.
- Quad geometry is cached in a `MTLBuffer` and rebuilt only when viewport size or texture size changes.
- Depth writes are disabled and depth compare is set to `.always`, so HUD stays on top.

## Data Flow
1. Frame update/render timings are produced in `Renderer.draw`.
2. Producer methods record timings/events into rolling buffers under `diagnosticsLock`.
3. Every `hudUpdateInterval` (`0.1s`), `updateHUD` computes a rolling snapshot.
4. Snapshot is formatted into HUD lines.
5. `HUDOverlayPass.update(lines:)` compares incoming lines with cached lines, and only regenerates when content changed.
6. `HUDOverlayPass.draw(...)` composites the panel into the current frame.

## HUD Overlay Optimizations
- Content-change short-circuit:
`HUDOverlayPass.update(lines:)` exits early when text lines are unchanged.
- Texture reuse:
`overlayTexture` and `overlaySpareTexture` are reused via `replace(region:...)` to avoid per-update texture allocation.
- Cached quad buffer:
The HUD quad vertices are stored in `quadVertexBuffer` and updated only on size changes.
- Reduced lock contention:
`overlayTextureLock` mainly guards fast state swaps; expensive bitmap generation and upload occur outside the lock.
- Empty-state fast path:
When there are no lines, the pass clears active texture state instead of building/uploading a blank texture.

## Rolling Metrics Window
- HUD uses a rolling window of `1.5s` (`hudRollingWindowSeconds`).
- Metrics are trimmed by timestamp each time producers push samples.
- Displayed values are sliding-window aggregates, not tumbling-window reset averages.

## Metrics Displayed
- CPU update ms (avg)
- CPU render ms (avg)
- CPU frame gap ms (avg + max)
- Pass timings (avg per pass)
- GPU command buffer latency ms (avg)
- Main queue latency ms (avg + max + threshold rates)
- Gap spike rates (`>33ms`, `>100ms`)
- Sink publish rates (scene/xform/interp per second)
- In-flight command buffer count and rolling peak

## Controls and Settings
- `hudLevel`: `off`, `basic`, `verbose`.
- `toggleHUD()`: cycles `off -> basic -> verbose -> off` (mapped to `H` key path).
- `showHUD`: compatibility convenience (`hudLevel != .off`).
- `enableDiagnosticsLogDump`: enables periodic console dump.
- `toggleDiagnosticsLogDump()`: runtime toggle for dump mode.

## Diagnostics Dump (Unchanged)
- Dump path remains separate from HUD rolling display.
- Uses `diagnosticsDump*` accumulators and a fixed `30s` dump interval.
- Console output includes CPU/GPU/main-queue/gap/sink/app-state summaries.
- HUD rolling conversion does not change dump semantics.

## Threading and Synchronization
- `diagnosticsLock` protects producer/consumer access to diagnostics state.
- Command-buffer completion callbacks and main-queue probe callbacks can occur asynchronously.
- HUD texture state in `HUDOverlayPass` is protected by `overlayTextureLock`.
- HUD overlay update work is split so lock-held sections stay short.

## Visual Layout Notes
- Top-left anchored panel.
- Current margins: `marginX = 16`, `marginY = 34`.
- Larger text sizing is enabled for readability:
  - Title font: 17
  - Body font: 15
