//
//  InterpolationLabTypes.swift
//  RenderLab
//
//  Shared UI/renderer domain types for Interpolation Lab.
//

import Foundation

enum InterpolationScalarMode: Int32, CaseIterable, Codable {
    case lerp = 0
    case smoothstep = 1
    case cubic = 2

    var displayName: String {
        switch self {
        case .lerp: return "Lerp"
        case .smoothstep: return "Smoothstep"
        case .cubic: return "Cubic"
        }
    }
}

enum InterpolationRotationMode: Int32, CaseIterable, Codable {
    case eulerLerp = 0
    case quaternionNlerp = 1
    case quaternionSlerp = 2

    var displayName: String {
        switch self {
        case .eulerLerp: return "Euler Lerp"
        case .quaternionNlerp: return "Quat Nlerp"
        case .quaternionSlerp: return "Quat Slerp"
        }
    }
}

enum InterpolationLoopMode: Int32, CaseIterable, Codable {
    case clamp = 0
    case loop = 1
    case pingPong = 2

    var displayName: String {
        switch self {
        case .clamp: return "Clamp"
        case .loop: return "Loop"
        case .pingPong: return "Ping-Pong"
        }
    }
}

struct InterpolationLabSnapshot: Equatable {
    var selectedObjectID: UInt32?
    var selectedObjectName: String?
    var hasKeyframeA: Bool
    var hasKeyframeB: Bool
    var keyframeA: SceneTransform?
    var keyframeB: SceneTransform?
    var t: Float
    var isPlaying: Bool
    var speed: Float
    var loopMode: InterpolationLoopMode
    var positionMode: InterpolationScalarMode
    var rotationMode: InterpolationRotationMode
    var scaleMode: InterpolationScalarMode
    var shortestPath: Bool
    var showGhostA: Bool
    var showGhostB: Bool
    var interpolatedTransform: SceneTransform?
    var distanceToA: Float?
    var distanceToB: Float?

    static let empty = InterpolationLabSnapshot(
        selectedObjectID: nil,
        selectedObjectName: nil,
        hasKeyframeA: false,
        hasKeyframeB: false,
        keyframeA: nil,
        keyframeB: nil,
        t: 0.0,
        isPlaying: false,
        speed: 1.0,
        loopMode: .clamp,
        positionMode: .lerp,
        rotationMode: .quaternionSlerp,
        scaleMode: .lerp,
        shortestPath: true,
        showGhostA: true,
        showGhostB: true,
        interpolatedTransform: nil,
        distanceToA: nil,
        distanceToB: nil
    )
}
