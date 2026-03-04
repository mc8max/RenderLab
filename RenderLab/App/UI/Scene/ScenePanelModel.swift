//
//  ScenePanelModel.swift
//  RenderLab
//
//  UI-facing scene list state.
//

import Foundation
import Combine

final class ScenePanelModel: ObservableObject {
    @Published private(set) var objects: [ScenePanelObjectSnapshot] = []
    @Published private(set) var selectedObjectID: UInt32?

    var selectedObject: ScenePanelObjectSnapshot? {
        guard let selectedObjectID else { return nil }
        return objects.first(where: { $0.id == selectedObjectID })
    }

    func setLocalSelection(_ objectID: UInt32?) {
        selectedObjectID = objectID
    }

    func setLocalVisibility(objectID: UInt32, isVisible: Bool) {
        if let index = objects.firstIndex(where: { $0.id == objectID }) {
            objects[index].isVisible = isVisible
        }
    }

    func setLocalTransform(objectID: UInt32, transform: SceneTransform) {
        if let index = objects.firstIndex(where: { $0.id == objectID }) {
            objects[index].transform = transform
        }
    }

}

extension ScenePanelModel: RendererSceneSink {
    func applySceneSnapshot(_ snapshot: ScenePanelSnapshot) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.objects = snapshot.objects
            self.selectedObjectID = snapshot.selectedObjectID
        }
    }
}
