//
//  SceneTransformBridge.swift
//  RenderLab
//
//  Centralized conversion helpers between Swift and C bridge transforms.
//

import simd

extension SceneTransform {
    func toCoreSceneTransform() -> CoreSceneTransform {
        var raw = CoreSceneTransform()
        raw.position = (position.x, position.y, position.z)
        raw.rotation = (rotation.x, rotation.y, rotation.z)
        raw.scale = (scale.x, scale.y, scale.z)
        return raw
    }

    static func fromCoreSceneTransform(_ transform: CoreSceneTransform) -> SceneTransform {
        SceneTransform(
            position: SIMD3<Float>(transform.position.0, transform.position.1, transform.position.2),
            rotation: SIMD3<Float>(transform.rotation.0, transform.rotation.1, transform.rotation.2),
            scale: SIMD3<Float>(transform.scale.0, transform.scale.1, transform.scale.2)
        )
    }
}
