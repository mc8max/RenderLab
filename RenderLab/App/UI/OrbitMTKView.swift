//
//  OrbitMTKView.swift
//  RenderLab
//
//  Created by Hoàng Trí Tâm on 22/2/26.
//

import AppKit
import MetalKit

final class OrbitMTKView: MTKView {
    var onOrbitDrag: ((Float, Float) -> Void)?
    var onPanDrag: ((Float, Float) -> Void)?
    var onZoom: ((Float) -> Void)?
    var onDebugModeKey: ((Int32) -> Void)?
    var onToggleGridKey: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        // Shift + left drag pans to support trackpads/single-button setups.
        if event.modifierFlags.contains(.shift) {
            onPanDrag?(Float(event.deltaX), Float(event.deltaY))
            return
        }
        onOrbitDrag?(Float(event.deltaX), Float(event.deltaY))
    }

    override func rightMouseDragged(with event: NSEvent) {
        onPanDrag?(Float(event.deltaX), Float(event.deltaY))
    }

    override func otherMouseDragged(with event: NSEvent) {
        onPanDrag?(Float(event.deltaX), Float(event.deltaY))
    }

    override func scrollWheel(with event: NSEvent) {
        // Optional: ignore inertial/momentum scroll for more controllable zoom
        if !event.momentumPhase.isEmpty {
            return
        }

        // Trackpad usually reports precise deltas; mouse wheel is coarse "step" deltas.
        let rawY: CGFloat
        if event.hasPreciseScrollingDeltas {
            rawY = event.scrollingDeltaY
        } else {
            // Mouse wheel: amplify a bit because wheel steps are coarse
            rawY = event.scrollingDeltaY * 8.0
        }

        onZoom?(Float(rawY))
    }

    override func keyDown(with event: NSEvent) {
        let panStep: Float = event.modifierFlags.contains(.shift) ? 24.0 : 12.0
        switch event.keyCode {
        case 123: // Left arrow
            onPanDrag?(-panStep, 0)
            return
        case 124: // Right arrow
            onPanDrag?(panStep, 0)
            return
        case 125: // Down arrow
            onPanDrag?(0, -panStep)
            return
        case 126: // Up arrow
            onPanDrag?(0, panStep)
            return
        default:
            break
        }

        switch event.charactersIgnoringModifiers {
        case "1":
            onDebugModeKey?(0)  // VertexColor
        case "2":
            onDebugModeKey?(1)  // FlatWhite
        case "3":
            onDebugModeKey?(2)  // RawDepth
        case "4":
            onDebugModeKey?(3) // LinearDepth
        case "g", "G":
            onToggleGridKey?()
        default:
            super.keyDown(with: event)
        }
    }
}
