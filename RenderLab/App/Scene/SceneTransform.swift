//
//  SceneTransform.swift
//  RenderLab
//
//  Domain transform used by scene object snapshots and mutations.
//

import simd

struct SceneTransform {
    var position: SIMD3<Float> = .zero
    var rotation: SIMD3<Float> = .zero
    var scale: SIMD3<Float> = SIMD3<Float>(repeating: 1.0)
}
