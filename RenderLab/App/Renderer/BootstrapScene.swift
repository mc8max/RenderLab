//
//  BootstrapScene.swift
//  RenderLab
//
//  Default scene bootstrap with starter objects.
//

import simd
import Foundation

enum BootstrapScene {
    private static let teamUGMeshID: UInt32 = 100
    private static let fallbackMeshID: UInt32 = RenderAssets.BuiltInMeshID.cube.rawValue

    static func loadDefaultObjects(into scene: CoreScene, renderAssets: RenderAssets) {
        guard scene.count == 0 else { return }

        guard let objURL = resolveTeamUGOBJURL() else {
            print("BootstrapScene: could not resolve OBJ path Assets/Sample/teamugobj.obj")
            addFallbackCube(into: scene, renderAssets: renderAssets)
            return
        }

        do {
            try renderAssets.registerOBJ(meshID: teamUGMeshID, from: objURL)
        } catch {
            print("BootstrapScene: OBJ preload failed: \(error.localizedDescription)")
            addFallbackCube(into: scene, renderAssets: renderAssets)
            return
        }

        addObject(
            into: scene,
            meshID: teamUGMeshID,
            materialID: 0,
            transform: SceneTransform(
                position: SIMD3<Float>(0.0, 0.0, 0.0),
                rotation: SIMD3<Float>(0.0, 0.0, 0.0),
                scale: SIMD3<Float>(repeating: 2.0 / 3.0)
            )
        )
    }

    private static func addFallbackCube(into scene: CoreScene, renderAssets: RenderAssets) {
        if renderAssets.mesh(for: fallbackMeshID) == nil {
            guard renderAssets.registerCube(meshID: fallbackMeshID) else {
                print("BootstrapScene: fallback cube registration failed.")
                return
            }
        }

        addObject(
            into: scene,
            meshID: fallbackMeshID,
            materialID: 0,
            transform: SceneTransform(
                position: SIMD3<Float>(0.0, 0.0, 0.0),
                rotation: SIMD3<Float>(0.0, 0.0, 0.0),
                scale: SIMD3<Float>(repeating: 1.0)
            )
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
    ) {
        let objectID = scene.add(meshID: meshID, materialID: materialID)
        guard objectID != 0 else { return }
        _ = scene.setTransform(objectID: objectID, transform: transform)
        _ = scene.setVisible(objectID: objectID, isVisible: true)
    }
}
