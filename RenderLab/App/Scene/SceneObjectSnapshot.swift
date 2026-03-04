//
//  SceneObjectSnapshot.swift
//  RenderLab
//
//  Read-only scene object data returned from CoreScene bridge.
//

import Foundation

struct SceneObjectSnapshot {
    let objectID: UInt32
    let meshID: UInt32
    let materialID: UInt32
    var transform: SceneTransform
    var isVisible: Bool
}
