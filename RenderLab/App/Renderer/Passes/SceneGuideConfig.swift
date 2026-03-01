//
//  SceneGuideConfig.swift
//  RenderLab
//
//  Shared layout constants for scene guide rendering (grid + axis).
//

import Foundation

enum SceneGuideConfig {
    static let gridHalfLineCount: Int = 10
    static let gridSpacing: Float = 1.0
    static let gridPlaneY: Float = -0.501

    static var gridExtent: Float {
        Float(gridHalfLineCount) * gridSpacing
    }

    static var axisExtent: Float {
        gridExtent
    }
}
