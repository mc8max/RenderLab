# Backlog

1. view.draw() is still scheduled on the main thread
- Display-link pacing helps, but if SwiftUI/main thread is busy, frames can still be delayed.

2. UI/state sync still uses main-thread async dispatch heavily
- Many controls and sink updates (scene/xform/interp) can create bursty main-queue pressure.

3. Scene sync rebuilds full snapshot structures
- Fine for small scenes, but scales poorly with many objects.

4. CVDisplayLink path is using deprecated APIs
- Not an immediate FPS bug, but should migrate to new macOS display link APIs to avoid future behavior changes.

5. Diagnostics are always running
- Low overhead now, but continuous logging/probing should stay debug-only.
