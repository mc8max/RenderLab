//
//  SceneTransform.swift
//  RenderLab
//
//  Domain transform used by scene object snapshots and mutations.
//

import simd

struct SceneTransform: Equatable {
    var position: SIMD3<Float> = .zero
    var rotation: SIMD3<Float> = .zero
    var scale: SIMD3<Float> = SIMD3<Float>(repeating: 1.0)
}

extension SceneTransform {
    func modelMatrix() -> simd_float4x4 {
        translationMatrix(position)
            * rotationMatrix(rotation)
            * scaleMatrix(scale)
    }

    func pivotPoint() -> SIMD3<Float> {
        position
    }

    func isApproximatelyEqual(to other: SceneTransform, epsilon: Float = 0.0001) -> Bool {
        simd.length(position - other.position) <= epsilon
            && simd.length(rotation - other.rotation) <= epsilon
            && simd.length(scale - other.scale) <= epsilon
    }

    private func translationMatrix(_ t: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        )
    }

    private func rotationMatrix(_ r: SIMD3<Float>) -> simd_float4x4 {
        rotationZ(r.z) * rotationY(r.y) * rotationX(r.x)
    }

    private func scaleMatrix(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(s.x, 0, 0, 0),
            SIMD4<Float>(0, s.y, 0, 0),
            SIMD4<Float>(0, 0, s.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    private func rotationX(_ radians: Float) -> simd_float4x4 {
        let c = cos(radians)
        let s = sin(radians)
        return simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, c, s, 0),
            SIMD4<Float>(0, -s, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    private func rotationY(_ radians: Float) -> simd_float4x4 {
        let c = cos(radians)
        let s = sin(radians)
        return simd_float4x4(
            SIMD4<Float>(c, 0, -s, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(s, 0, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    private func rotationZ(_ radians: Float) -> simd_float4x4 {
        let c = cos(radians)
        let s = sin(radians)
        return simd_float4x4(
            SIMD4<Float>(c, s, 0, 0),
            SIMD4<Float>(-s, c, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
}
