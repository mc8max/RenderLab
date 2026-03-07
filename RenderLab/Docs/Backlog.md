# Backlog

## UI
Reduce the scene objects panel
Drop down the interpolation

## Design
1. view.draw() is still scheduled on the main thread
- Display-link pacing helps, but if SwiftUI/main thread is busy, frames can still be delayed.

2. UI/state sync still uses main-thread async dispatch heavily
- Many controls and sink updates (scene/xform/interp) can create bursty main-queue pressure.

3. Scene sync rebuilds full snapshot structures
- Fine for small scenes, but scales poorly with many objects.
