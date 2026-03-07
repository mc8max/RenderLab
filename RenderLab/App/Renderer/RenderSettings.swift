//
//  RenderSettings.swift
//  RenderLab
//
//  Created by Hoàng Trí Tâm on 27/2/26.
//
// Goal: one source of truth for all toggles/sliders the renderer reads each frame.

import Foundation
import Combine
import simd

// Keep your existing debug modes, but putting them here makes settings self-contained.
enum DebugMode: Int32, CaseIterable, Codable {
    case vertexColor = 0
    case flatWhite   = 1
    case rawDepth    = 2
    case linearDepth = 3

    var label: String {
        switch self {
        case .vertexColor: return "VertexColor"
        case .flatWhite:   return "FlatWhite"
        case .rawDepth:    return "RawDepth"
        case .linearDepth: return "LinearDepth"
        }
    }
}

enum DepthTest: Int, CaseIterable, Codable {
    case off = 0
    case lessEqual = 1

    var displayName: String {
        switch self {
        case .off:       return "Off"
        case .lessEqual: return "LessEqual"
        }
    }
}

enum CullMode: Int, CaseIterable, Codable {
    case none = 0
    case back = 1
    case front = 2

    var displayName: String {
        switch self {
        case .none:  return "None"
        case .back:  return "Back"
        case .front: return "Front"
        }
    }
}

enum ClearColorPreset: Int, CaseIterable, Codable {
    case neutralDark = 0
    case neutralGray = 1
    case white = 2
    case black = 3

    var displayName: String {
        switch self {
        case .neutralDark: return "Neutral Dark"
        case .neutralGray: return "Neutral Gray"
        case .white:       return "White"
        case .black:       return "Black"
        }
    }

    var rgba: SIMD4<Float> {
        switch self {
        case .neutralDark: return SIMD4<Float>(0.08, 0.09, 0.10, 1.0)
        case .neutralGray: return SIMD4<Float>(0.18, 0.18, 0.18, 1.0)
        case .white:       return SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
        case .black:       return SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
        }
    }
}

enum TransformSpace: Int, CaseIterable, Codable {
    case world = 0
    case local = 1

    var displayName: String {
        switch self {
        case .world: return "World"
        case .local: return "Local"
        }
    }
}

enum HUDLevel: Int, CaseIterable, Codable {
    case off = 0
    case basic = 1
    case verbose = 2

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .basic: return "Basic"
        case .verbose: return "Verbose"
        }
    }

    var next: HUDLevel {
        switch self {
        case .off: return .basic
        case .basic: return .verbose
        case .verbose: return .off
        }
    }
}

/// RenderSettings is meant to be *read every frame* by the renderer.
/// Keep it lightweight and deterministic.
@MainActor
final class RenderSettings: ObservableObject {

    // MARK: - Debug / visualization
    @Published var debugMode: DebugMode = .vertexColor

    // MARK: - Core pipeline toggles
    @Published var depthTest: DepthTest = .lessEqual
    @Published var cullMode: CullMode = .back

    // MARK: - View helpers (v0.1)
    @Published var showGrid: Bool = true
    @Published var showAxis: Bool = true
    @Published var showObjectBasis: Bool = true
    @Published var showPivot: Bool = true
    @Published var transformSpace: TransformSpace = .local

    // MARK: - Debug overlays
    @Published var showModelMatrixDebug: Bool = false
    @Published var hudLevel: HUDLevel = .basic
    @Published var suspendUISyncDuringPlayback: Bool = false
    @Published var enableDiagnosticsLogDump: Bool = false

    // MARK: - Clear / presentation
    @Published var clearColorPreset: ClearColorPreset = .neutralDark

    // MARK: - Depth debug parameters (you already have near/far in your shader debug params)
    // Keep these here so the shader debug always has access to the same values.
    @Published var cameraFovYDegrees: Float = 60.0
    @Published var cameraNear: Float = 0.05
    @Published var cameraFar: Float = 100.0

    // MARK: - Convenience
    /// Convert to a Metal-friendly clear color (no need to import Metal here).
    var clearColorRGBA: SIMD4<Float> { clearColorPreset.rgba }
    var showHUD: Bool {
        get { hudLevel != .off }
        set { hudLevel = newValue ? .verbose : .off }
    }

    /// Clamp sanity to avoid exploding depth visualization.
    func sanitize() {
        if cameraFovYDegrees < 1.0 { cameraFovYDegrees = 1.0 }
        if cameraFovYDegrees > 170.0 { cameraFovYDegrees = 170.0 }
        if cameraNear < 0.001 { cameraNear = 0.001 }
        if cameraFar < cameraNear + 0.01 { cameraFar = cameraNear + 0.01 }
    }

    // MARK: - Input hooks
    /// Map number keys 1-4 to debug modes. Call from your key handler.
    func setDebugModeFromNumberKey(_ n: Int32) {
        guard let mode = DebugMode(rawValue: n) else { return }
        debugMode = mode
    }

    /// Quick toggles you can wire to keys later (e.g., G for grid, H for HUD).
    func toggleGrid() { showGrid.toggle() }
    func toggleAxis() { showAxis.toggle() }
    func toggleObjectBasis() { showObjectBasis.toggle() }
    func togglePivot() { showPivot.toggle() }
    func toggleTransformSpace() {
        transformSpace = (transformSpace == .local) ? .world : .local
    }
    func toggleHUD()  { hudLevel = hudLevel.next }
    func toggleDiagnosticsLogDump() { enableDiagnosticsLogDump.toggle() }

    /// Optional: cycle debug modes with a single hotkey.
    func cycleDebugMode(forward: Bool = true) {
        let modes = DebugMode.allCases.sorted { $0.rawValue < $1.rawValue }
        guard let idx = modes.firstIndex(of: debugMode) else { return }
        let next = forward
            ? (idx + 1) % modes.count
            : (idx - 1 + modes.count) % modes.count
        debugMode = modes[next]
    }
}
