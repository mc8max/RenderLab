//
//  ScenePanelContracts.swift
//  RenderLab
//
//  Shared contracts for scene UI synchronization and commands.
//

import Foundation

struct ScenePanelObjectSnapshot: Identifiable, Equatable {
    let id: UInt32
    var name: String
    var isVisible: Bool
    var meshID: UInt32
    var materialID: UInt32
    var transform: SceneTransform
}

struct ScenePanelSnapshot {
    var objects: [ScenePanelObjectSnapshot]
    var selectedObjectID: UInt32?
}

protocol RendererSceneSink: AnyObject {
    func applySceneSnapshot(_ snapshot: ScenePanelSnapshot)
}

final class SceneCommandBridge {
    private var onSelectObject: ((UInt32?) -> Void)?
    private var onSetObjectVisibility: ((UInt32, Bool) -> Void)?
    private var onSetObjectTransform: ((UInt32, SceneTransform) -> Void)?
    private var onAddCube: (() -> Void)?

    func bindRendererActions(
        onSelectObject: @escaping (UInt32?) -> Void,
        onSetObjectVisibility: @escaping (UInt32, Bool) -> Void,
        onSetObjectTransform: @escaping (UInt32, SceneTransform) -> Void,
        onAddCube: @escaping () -> Void
    ) {
        self.onSelectObject = onSelectObject
        self.onSetObjectVisibility = onSetObjectVisibility
        self.onSetObjectTransform = onSetObjectTransform
        self.onAddCube = onAddCube
    }

    func selectObject(_ objectID: UInt32?) {
        onSelectObject?(objectID)
    }

    func setObjectVisibility(objectID: UInt32, isVisible: Bool) {
        onSetObjectVisibility?(objectID, isVisible)
    }

    func setObjectTransform(objectID: UInt32, transform: SceneTransform) {
        onSetObjectTransform?(objectID, transform)
    }

    func addCubeObject() {
        onAddCube?()
    }
}
