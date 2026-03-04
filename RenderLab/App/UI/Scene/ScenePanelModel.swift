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

    func setLocalSelection(_ objectID: UInt32?) {
        selectedObjectID = objectID
    }

    func setLocalVisibility(objectID: UInt32, isVisible: Bool) {
        if let index = objects.firstIndex(where: { $0.id == objectID }) {
            objects[index].isVisible = isVisible
        }
    }
}

extension ScenePanelModel: RendererSceneSink {
    func applySceneSnapshot(_ snapshot: ScenePanelSnapshot) {
        let apply = {
            self.objects = snapshot.objects
            self.selectedObjectID = snapshot.selectedObjectID
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}
