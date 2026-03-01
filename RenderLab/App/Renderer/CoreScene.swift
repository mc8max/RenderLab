//
//  CoreScene.swift
//  RenderLab
//
//  Swift wrapper for CoreCPP scene ownership and object operations.
//

import Foundation
import simd

struct SceneTransform {
    var position: SIMD3<Float> = .zero
    var rotation: SIMD3<Float> = .zero
    var scale: SIMD3<Float> = SIMD3<Float>(repeating: 1.0)
}

struct SceneObject {
    let objectID: UInt32
    let meshID: UInt32
    let materialID: UInt32
    var transform: SceneTransform
    var isVisible: Bool
}

final class CoreScene {
    private var handle: OpaquePointer?

    init(initialCapacity: UInt32 = 64) {
        self.handle = coreSceneCreate(initialCapacity)
        precondition(self.handle != nil, "Failed to create CoreSceneHandle from CoreCPP.")
    }

    deinit {
        if let handle {
            coreSceneDestroy(handle)
        }
    }

    var count: UInt32 {
        guard let handle else { return 0 }
        return coreSceneCount(handle)
    }

    @discardableResult
    func add(meshID: UInt32, materialID: UInt32) -> UInt32 {
        guard let handle else { return 0 }
        return coreSceneAdd(handle, meshID, materialID)
    }

    func find(objectID: UInt32) -> SceneObject? {
        guard let handle else { return nil }

        var raw = CoreSceneObjectData()
        let found = coreSceneFind(handle, objectID, &raw)
        guard found != 0 else { return nil }

        return makeSceneObject(from: raw)
    }

    func object(at index: UInt32) -> SceneObject? {
        guard let handle else { return nil }

        var raw = CoreSceneObjectData()
        let found = coreSceneGetByIndex(handle, index, &raw)
        guard found != 0 else { return nil }

        return makeSceneObject(from: raw)
    }

    func allObjects() -> [SceneObject] {
        let totalCount = count
        if totalCount == 0 { return [] }

        var objects: [SceneObject] = []
        objects.reserveCapacity(Int(totalCount))
        for index in 0..<totalCount {
            if let object = object(at: index) {
                objects.append(object)
            }
        }
        return objects
    }

    private func makeSceneObject(from raw: CoreSceneObjectData) -> SceneObject {
        return SceneObject(
            objectID: raw.objectID,
            meshID: raw.meshID,
            materialID: raw.materialID,
            transform: fromCTransform(raw.transform),
            isVisible: raw.visible != 0
        )
    }

    @discardableResult
    func setTransform(objectID: UInt32, transform: SceneTransform) -> Bool {
        guard let handle else { return false }
        var raw = toCTransform(transform)
        return coreSceneSetTransform(handle, objectID, &raw) != 0
    }

    @discardableResult
    func setVisible(objectID: UInt32, isVisible: Bool) -> Bool {
        guard let handle else { return false }
        return coreSceneSetVisible(handle, objectID, isVisible ? 1 : 0) != 0
    }

    private func toCTransform(_ transform: SceneTransform) -> CoreSceneTransform {
        var raw = CoreSceneTransform()
        raw.position = (transform.position.x, transform.position.y, transform.position.z)
        raw.rotation = (transform.rotation.x, transform.rotation.y, transform.rotation.z)
        raw.scale = (transform.scale.x, transform.scale.y, transform.scale.z)
        return raw
    }

    private func fromCTransform(_ transform: CoreSceneTransform) -> SceneTransform {
        return SceneTransform(
            position: SIMD3<Float>(transform.position.0, transform.position.1, transform.position.2),
            rotation: SIMD3<Float>(transform.rotation.0, transform.rotation.1, transform.rotation.2),
            scale: SIMD3<Float>(transform.scale.0, transform.scale.1, transform.scale.2)
        )
    }
}
