# Frame Rate Problem
  - FPS started near 60, then decayed over time (40, 25, sometimes much lower) during interpolation playback.
  - Decay happened even though scene complexity and rendering passes were unchanged.

## Root Causes
  - Rendering was not GPU/renderer bound: update and render CPU times stayed very low, GPU command latency stayed low.
  - Large frame scheduling gaps dominated frame time (gap and gapMax spikes), meaning draw callbacks were delayed/starved.
  - Main thread intermittently stalled (mainQMs spikes), causing missed frame cadence.
  - When app/window became inactive or occluded, macOS deprioritized/throttled execution further.
  - App Nap/background behavior also contributed during long playback.

## Solutions Tried (Earlier, Limited Impact)
  - Reduced/interleaved interpolation and transform publish rates.
  - Added UI sync throttling options and sink coalescing.
  - Disabled/trimmed readout sections and changed transform editing flow.
  - Added periodic diagnostics dumps every 30s and expanded instrumentation.
  - Fixed SwiftUI publish-timing warning paths (Publishing changes from within view updates...) via safer async mutation paths.

## Solutions Implemented (Effective)
  - Added deep diagnostics: frame-gap spikes, main-queue latency, app/window/runtime state.
  - Suspended UI sync updates while app is inactive/occluded (scene snapshot, transform, interpolation, HUD updates).
  - Added App Nap suppression during active interpolation playback (beginActivity/endActivity).
  - Moved frame pacing to display-link-driven scheduling.

## Current Status

  - Frame rate is now stable/good under the updated pipeline.
