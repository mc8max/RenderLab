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
    static let axisArrowHeadLength: Float = 0.8
    static let axisArrowHeadWidth: Float = 0.35

    static let objectBasisExtent: Float = 0.9
    static let objectBasisArrowHeadLength: Float = 0.16
    static let objectBasisArrowHeadWidth: Float = 0.07
    static let pivotMarkerExtent: Float = 0.14
}
