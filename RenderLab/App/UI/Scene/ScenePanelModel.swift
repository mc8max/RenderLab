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

    private let pendingSinkLock = NSLock()
    private var pendingSceneSnapshot: ScenePanelSnapshot?
    private var pendingSelectedTransform: (objectID: UInt32, transform: SceneTransform)?
    private var pendingInterpolationSnapshot: InterpolationLabSnapshot?
    private var isPendingSinkFlushScheduled: Bool = false

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
        if Thread.isMainThread {
            objects = snapshot.objects
            selectedObjectID = snapshot.selectedObjectID
            return
        }
        enqueuePendingSinkUpdates(sceneSnapshot: snapshot, selectedTransform: nil, interpolationSnapshot: nil)
    }

    func applyInterpolationSnapshot(_ snapshot: InterpolationLabSnapshot) {
        if Thread.isMainThread {
            interpolationLab = snapshot
            return
        }
        enqueuePendingSinkUpdates(sceneSnapshot: nil, selectedTransform: nil, interpolationSnapshot: snapshot)
    }

    func applySelectedObjectTransform(objectID: UInt32, transform: SceneTransform) {
        if Thread.isMainThread {
            setLocalTransform(objectID: objectID, transform: transform)
            return
        }
        enqueuePendingSinkUpdates(
            sceneSnapshot: nil,
            selectedTransform: (objectID: objectID, transform: transform),
            interpolationSnapshot: nil
        )
    }

    private func enqueuePendingSinkUpdates(
        sceneSnapshot: ScenePanelSnapshot?,
        selectedTransform: (objectID: UInt32, transform: SceneTransform)?,
        interpolationSnapshot: InterpolationLabSnapshot?
    ) {
        pendingSinkLock.lock()
        if let sceneSnapshot {
            pendingSceneSnapshot = sceneSnapshot
        }
        if let selectedTransform {
            pendingSelectedTransform = selectedTransform
        }
        if let interpolationSnapshot {
            pendingInterpolationSnapshot = interpolationSnapshot
        }
        let shouldSchedule = isPendingSinkFlushScheduled == false
        if shouldSchedule {
            isPendingSinkFlushScheduled = true
        }
        pendingSinkLock.unlock()

        guard shouldSchedule else { return }
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingSinkUpdatesOnMain()
        }
    }

    private func flushPendingSinkUpdatesOnMain() {
        let sceneSnapshot: ScenePanelSnapshot?
        let selectedTransform: (objectID: UInt32, transform: SceneTransform)?
        let interpolationSnapshot: InterpolationLabSnapshot?

        pendingSinkLock.lock()
        sceneSnapshot = pendingSceneSnapshot
        selectedTransform = pendingSelectedTransform
        interpolationSnapshot = pendingInterpolationSnapshot
        pendingSceneSnapshot = nil
        pendingSelectedTransform = nil
        pendingInterpolationSnapshot = nil
        isPendingSinkFlushScheduled = false
        pendingSinkLock.unlock()

        if let sceneSnapshot {
            objects = sceneSnapshot.objects
            selectedObjectID = sceneSnapshot.selectedObjectID
        }
        if let selectedTransform {
            setLocalTransform(objectID: selectedTransform.objectID, transform: selectedTransform.transform)
        }
        if let interpolationSnapshot {
            interpolationLab = interpolationSnapshot
        }
    }
}
