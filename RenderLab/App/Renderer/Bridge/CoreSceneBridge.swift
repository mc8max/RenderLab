//
//  CoreSceneBridge.swift
//  RenderLab
//
//  Swift wrapper for CoreCPP scene ownership and object operations.
//

import Foundation

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

    func find(objectID: UInt32) -> SceneObjectSnapshot? {
        guard let handle else { return nil }

        var raw = CoreSceneObjectData()
        let found = coreSceneFind(handle, objectID, &raw)
        guard found != 0 else { return nil }

        return makeSceneObject(from: raw)
    }

    func object(at index: UInt32) -> SceneObjectSnapshot? {
        guard let handle else { return nil }

        var raw = CoreSceneObjectData()
        let found = coreSceneGetByIndex(handle, index, &raw)
        guard found != 0 else { return nil }

        return makeSceneObject(from: raw)
    }

    func allObjects() -> [SceneObjectSnapshot] {
        let totalCount = count
        if totalCount == 0 { return [] }

        var objects: [SceneObjectSnapshot] = []
        objects.reserveCapacity(Int(totalCount))
        for index in 0..<totalCount {
            if let object = object(at: index) {
                objects.append(object)
            }
        }
        return objects
    }

    private func makeSceneObject(from raw: CoreSceneObjectData) -> SceneObjectSnapshot {
        return SceneObjectSnapshot(
            objectID: raw.objectID,
            meshID: raw.meshID,
            materialID: raw.materialID,
            transform: SceneTransform.fromCoreSceneTransform(raw.transform),
            isVisible: raw.visible != 0
        )
    }

    @discardableResult
    func setTransform(objectID: UInt32, transform: SceneTransform) -> Bool {
        guard let handle else { return false }
        var raw = transform.toCoreSceneTransform()
        return coreSceneSetTransform(handle, objectID, &raw) != 0
    }

    @discardableResult
    func setVisible(objectID: UInt32, isVisible: Bool) -> Bool {
        guard let handle else { return false }
        return coreSceneSetVisible(handle, objectID, isVisible ? 1 : 0) != 0
    }
}
