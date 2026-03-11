//
//  Renderer+SceneEditing.swift
//  RenderLab
//
//  Scene selection, visibility, and object creation commands.
//

import simd

extension Renderer {
    func setSelectedObjectID(_ objectID: UInt32?) {
        if let objectID, scene.find(objectID: objectID) == nil {
            return
        }
        selectedObjectID = objectID
        refreshSelectedObjectCacheFromSceneForCurrentSelection()
        syncInterpolationSelectionState()
        syncScenePanelState()
        publishSkinningSnapshot(force: true)
    }

    func setObjectVisibility(objectID: UInt32, isVisible: Bool) {
        guard scene.setVisible(objectID: objectID, isVisible: isVisible) else {
            syncScenePanelState()
            return
        }
        if selectedObjectCache?.objectID == objectID {
            selectedObjectCache?.isVisible = isVisible
        }
        syncScenePanelState()
    }

    func setObjectTransform(objectID: UInt32, transform: SceneTransform) {
        guard scene.setTransform(objectID: objectID, transform: transform) else {
            syncScenePanelState()
            return
        }
        if interpolationLabState.objectID == objectID {
            if interpolationLabState.keyframeA == nil || interpolationLabState.keyframeB == nil {
                interpolationLabState.interpolatedTransform = transform
                interpolationLabState.distanceToA = nil
                interpolationLabState.distanceToB = nil
            }
        }
        if selectedObjectCache?.objectID == objectID {
            selectedObjectCache?.transform = transform
        }
        if let sceneSink, shouldSuspendUISyncForBackgroundState() == false {
            recordSelectedTransformPublish()
            sceneSink.applySelectedObjectTransform(objectID: objectID, transform: transform)
        }
        if interpolationLabState.objectID == objectID {
            publishInterpolationSnapshot(force: true)
        }
    }

    func addCubeObject() {
        guard let renderAssets else { return }

        let cubeMeshID = RenderAssets.BuiltInMeshID.cube.rawValue
        if renderAssets.mesh(for: cubeMeshID) == nil {
            guard renderAssets.registerCube(meshID: cubeMeshID) else {
                return
            }
        }

        let objectID = scene.add(meshID: cubeMeshID, materialID: 0)
        guard objectID != 0 else { return }

        let offsetX = Float(max(0, Int(scene.count) - 1)) * 1.25
        let transform = SceneTransform(
            position: SIMD3<Float>(offsetX, 0.0, 0.0),
            rotation: SIMD3<Float>(repeating: 0.0),
            scale: SIMD3<Float>(repeating: 1.0)
        )
        _ = scene.setTransform(objectID: objectID, transform: transform)
        _ = scene.setVisible(objectID: objectID, isVisible: true)

        objectNamesByID[objectID] = "Cube \(cubeNameCounter)"
        cubeNameCounter += 1
        selectedObjectID = objectID
        selectedObjectCache = SceneObjectSnapshot(
            objectID: objectID,
            meshID: cubeMeshID,
            materialID: 0,
            transform: transform,
            isVisible: true
        )
        syncInterpolationSelectionState()
        syncScenePanelState()
    }

    func syncScenePanelState(forcePublish: Bool = false) {
        let sceneObjects = scene.allObjects()
        for object in sceneObjects where objectNamesByID[object.objectID] == nil {
            objectNamesByID[object.objectID] = "Object \(object.objectID)"
        }

        if selectedObjectID == nil {
            selectedObjectID = sceneObjects.first?.objectID
        }

        if let selectedObjectID,
            sceneObjects.contains(where: { $0.objectID == selectedObjectID }) == false
        {
            self.selectedObjectID = sceneObjects.first?.objectID
        }

        if let selectedObjectID {
            selectedObjectCache = sceneObjects.first(where: { $0.objectID == selectedObjectID })
        } else {
            selectedObjectCache = nil
        }

        syncInterpolationSelectionState()

        let listObjects = sceneObjects.map { object in
            ScenePanelObjectSnapshot(
                id: object.objectID,
                name: objectNamesByID[object.objectID] ?? "Object \(object.objectID)",
                isVisible: object.isVisible,
                meshID: object.meshID,
                materialID: object.materialID,
                transform: object.transform
            )
        }
        let shouldPublish = forcePublish || shouldSuspendUISyncForBackgroundState() == false
        if let sceneSink, shouldPublish {
            recordSceneSnapshotPublish()
            sceneSink.applySceneSnapshot(
                ScenePanelSnapshot(
                    objects: listObjects,
                    selectedObjectID: selectedObjectID
                )
            )
        }
        publishInterpolationSnapshot(force: true)
        publishSkinningSnapshot(force: true)
    }

    func refreshSelectedObjectCacheFromSceneForCurrentSelection() {
        guard let selectedObjectID else {
            selectedObjectCache = nil
            return
        }
        selectedObjectCache = scene.find(objectID: selectedObjectID)
    }
}
