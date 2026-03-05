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
        syncInterpolationSelectionState()
        syncScenePanelState()
    }

    func setObjectVisibility(objectID: UInt32, isVisible: Bool) {
        guard scene.setVisible(objectID: objectID, isVisible: isVisible) else {
            syncScenePanelState()
            return
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
        syncScenePanelState()
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
        syncInterpolationSelectionState()
        syncScenePanelState()
    }

    func syncScenePanelState() {
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
        sceneSink?.applySceneSnapshot(
            ScenePanelSnapshot(
                objects: listObjects,
                selectedObjectID: selectedObjectID
            )
        )
        publishInterpolationSnapshot()
    }
}
