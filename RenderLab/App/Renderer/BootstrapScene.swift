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
    private static let fallbackMeshID: UInt32 = RenderAssets.BuiltInMeshID.cube.rawValue

    static func loadDefaultObjects(into scene: CoreScene, renderAssets: RenderAssets) -> InterpolationFrames? {
        guard scene.count == 0 else { return nil }

        guard let objURL = resolveTeamUGOBJURL() else {
            print("BootstrapScene: could not resolve OBJ path Assets/Sample/teamugobj.obj")
            return addFallbackCube(into: scene, renderAssets: renderAssets)
        }

        do {
            try renderAssets.registerOBJ(meshID: teamUGMeshID, from: objURL)
        } catch {
            print("BootstrapScene: OBJ preload failed: \(error.localizedDescription)")
            return addFallbackCube(into: scene, renderAssets: renderAssets)
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

    private static func addFallbackCube(into scene: CoreScene, renderAssets: RenderAssets) -> InterpolationFrames? {
        if renderAssets.mesh(for: fallbackMeshID) == nil {
            guard renderAssets.registerCube(meshID: fallbackMeshID) else {
                print("BootstrapScene: fallback cube registration failed.")
                return nil
            }
        }

        let frameA = SceneTransform(
            position: SIMD3<Float>(0.0, 0.0, 0.0),
            rotation: SIMD3<Float>(0.0, 0.0, 0.0),
            scale: SIMD3<Float>(repeating: 1.0)
        )
        guard let objectID = addObject(
            into: scene,
            meshID: fallbackMeshID,
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
