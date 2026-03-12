//
//  BootstrapScene.swift
//  RenderLab
//
//  Default scene bootstrap with starter objects.
//

import simd
import Foundation

enum BootstrapScene {
    struct InterpolationFrames {
        let objectID: UInt32
        let frameA: SceneTransform
        let frameB: SceneTransform
    }

    private static let teamUGMeshID: UInt32 = 100
    private static let skinningDemoMeshID: UInt32 = 1001
    private static let morphDemoMeshID: UInt32 = 1002
    static let enableDefaultSkinningDemoObject: Bool = false

    static func loadDefaultObjects(
        into scene: CoreScene,
        renderAssets: RenderAssets,
        preferTeamUGOBJ: Bool = false
    ) -> InterpolationFrames? {
        guard scene.count == 0 else { return nil }

        if preferTeamUGOBJ, let frames = addTeamUGOBJ(into: scene, renderAssets: renderAssets) {
            return frames
        }

        return nil
    }

    private static func addTeamUGOBJ(
        into scene: CoreScene,
        renderAssets: RenderAssets
    ) -> InterpolationFrames? {
        guard let objURL = resolveTeamUGOBJURL() else {
            print("BootstrapScene: could not resolve OBJ path Assets/Sample/teamugobj.obj")
            return nil
        }

        do {
            try renderAssets.registerOBJ(meshID: teamUGMeshID, from: objURL)
        } catch {
            print("BootstrapScene: OBJ preload failed: \(error.localizedDescription)")
            return nil
        }

        let frameA = SceneTransform(
            position: SIMD3<Float>(0.0, 0.0, 0.0),
            rotation: SIMD3<Float>(0.0, 0.0, 0.0),
            scale: SIMD3<Float>(repeating: 2.0 / 3.0)
        )
        guard let objectID = addObject(
            into: scene,
            meshID: teamUGMeshID,
            materialID: 0,
            transform: frameA
        ) else {
            return nil
        }
        return InterpolationFrames(
            objectID: objectID,
            frameA: frameA,
            frameB: makeDefaultFrameB(from: frameA)
        )
    }

    static func addSkinningDemoObject(into scene: CoreScene, renderAssets: RenderAssets) -> UInt32? {
        if renderAssets.mesh(for: skinningDemoMeshID) == nil {
            guard renderAssets.registerSkinnedRibbon(meshID: skinningDemoMeshID) else {
                print("BootstrapScene: skinning demo mesh registration failed.")
                return nil
            }
        }

        let transform = SceneTransform(
            position: SIMD3<Float>(0.0, 0.0, 0.0),
            rotation: SIMD3<Float>(repeating: 0.0),
            scale: SIMD3<Float>(repeating: 1.0)
        )
        return addObject(
            into: scene,
            meshID: skinningDemoMeshID,
            materialID: 0,
            transform: transform
        )
    }

    static func addMorphDemoObject(into scene: CoreScene, renderAssets: RenderAssets) -> UInt32? {
        if renderAssets.mesh(for: morphDemoMeshID) == nil {
            guard renderAssets.registerMorphRibbon(meshID: morphDemoMeshID) else {
                print("BootstrapScene: morph demo mesh registration failed.")
                return nil
            }
        }

        let transform = SceneTransform(
            position: SIMD3<Float>(-0.9, 0.0, 0.0),
            rotation: SIMD3<Float>(repeating: 0.0),
            scale: SIMD3<Float>(repeating: 1.0)
        )
        return addObject(
            into: scene,
            meshID: morphDemoMeshID,
            materialID: 0,
            transform: transform
        )
    }

    private static func resolveTeamUGOBJURL() -> URL? {
        if let bundled = Bundle.main.url(
            forResource: "teamugobj",
            withExtension: "obj"
        ) {
            return bundled
        }

        if let bundled = Bundle.main.url(
            forResource: "teamugobj",
            withExtension: "obj",
            subdirectory: "Assets/Sample"
        ) {
            return bundled
        }

        let repoRelative = URL(fileURLWithPath: "Assets/Sample/teamugobj.obj", isDirectory: false)
        if FileManager.default.fileExists(atPath: repoRelative.path) {
            return repoRelative
        }

        let cwdRelative = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Assets/Sample/teamugobj.obj")
        if FileManager.default.fileExists(atPath: cwdRelative.path) {
            return cwdRelative
        }

        return nil
    }

    private static func addObject(
        into scene: CoreScene,
        meshID: UInt32,
        materialID: UInt32,
        transform: SceneTransform
    ) -> UInt32? {
        let objectID = scene.add(meshID: meshID, materialID: materialID)
        guard objectID != 0 else { return nil }
        _ = scene.setTransform(objectID: objectID, transform: transform)
        _ = scene.setVisible(objectID: objectID, isVisible: true)
        return objectID
    }

    private static func makeDefaultFrameB(from frameA: SceneTransform) -> SceneTransform {
        SceneTransform(
            position: frameA.position + SIMD3<Float>(2.0, 1.35, -0.55),
            rotation: frameA.rotation + SIMD3<Float>(
                degreesToRadians(40.0),
                degreesToRadians(50.0),
                degreesToRadians(-36.0)
            ),
            scale: frameA.scale
        )
    }

    private static func degreesToRadians(_ degrees: Float) -> Float {
        degrees * .pi / 180.0
    }
}
