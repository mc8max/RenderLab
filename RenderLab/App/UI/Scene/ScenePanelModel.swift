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
    @Published private(set) var interpolationLab: InterpolationLabSnapshot = .empty

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

    func setLocalInterpolationTime(_ t: Float) {
        interpolationLab.t = min(max(t, 0.0), 1.0)
    }

    func setLocalInterpolationPlaying(_ isPlaying: Bool) {
        interpolationLab.isPlaying = isPlaying
    }

    func setLocalInterpolationSpeed(_ speed: Float) {
        let clamped = max(0.0, speed)
        DispatchQueue.main.async { [weak self] in
            self?.interpolationLab.speed = clamped
        }
    }

    func setLocalInterpolationLoopMode(_ mode: InterpolationLoopMode) {
        DispatchQueue.main.async { [weak self] in
            self?.interpolationLab.loopMode = mode
        }
    }

    func setLocalInterpolationPositionMode(_ mode: InterpolationScalarMode) {
        interpolationLab.positionMode = mode
    }

    func setLocalInterpolationRotationMode(_ mode: InterpolationRotationMode) {
        interpolationLab.rotationMode = mode
    }

    func setLocalInterpolationScaleMode(_ mode: InterpolationScalarMode) {
        interpolationLab.scaleMode = mode
    }

    func setLocalInterpolationShortestPath(_ enabled: Bool) {
        interpolationLab.shortestPath = enabled
    }

    func setLocalInterpolationShowGhostA(_ show: Bool) {
        interpolationLab.showGhostA = show
    }

    func setLocalInterpolationShowGhostB(_ show: Bool) {
        interpolationLab.showGhostB = show
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

    func applyInterpolationSnapshot(_ snapshot: InterpolationLabSnapshot) {
        DispatchQueue.main.async { [weak self] in
            self?.interpolationLab = snapshot
        }
    }

    func applySelectedObjectTransform(objectID: UInt32, transform: SceneTransform) {
        DispatchQueue.main.async { [weak self] in
            self?.setLocalTransform(objectID: objectID, transform: transform)
        }
    }
}
