//
//  BootstrapScene.swift
//  RenderLab
//
//  Default scene bootstrap with starter objects.
//

import simd

enum BootstrapScene {
    static func loadDefaultObjects(into scene: CoreScene) {
        guard scene.count == 0 else { return }

        addObject(
            into: scene,
            meshID: RenderAssets.BuiltInMeshID.cube.rawValue,
            materialID: 0,
            transform: SceneTransform(
                position: SIMD3<Float>(0.0, 0.0, 0.0),
                rotation: SIMD3<Float>(0.0, 0.0, 0.0),
                scale: SIMD3<Float>(repeating: 1.0)
            )
        )

        addObject(
            into: scene,
            meshID: RenderAssets.BuiltInMeshID.cube.rawValue,
            materialID: 1,
            transform: SceneTransform(
                position: SIMD3<Float>(1.35, 0.0, -0.35),
                rotation: SIMD3<Float>(0.0, 0.55, 0.0),
                scale: SIMD3<Float>(repeating: 0.65)
            )
        )
    }

    private static func addObject(
        into scene: CoreScene,
        meshID: UInt32,
        materialID: UInt32,
        transform: SceneTransform
    ) {
        let objectID = scene.add(meshID: meshID, materialID: materialID)
        guard objectID != 0 else { return }
        _ = scene.setTransform(objectID: objectID, transform: transform)
        _ = scene.setVisible(objectID: objectID, isVisible: true)
    }
}
