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

struct SkinningLabSnapshot: Equatable {
    var selectedObjectID: UInt32?
    var selectedObjectName: String?
    var isSelectedObjectSkinned: Bool
    var skinningEnabled: Bool
    var isPlaying: Bool
    var playbackTime: Float
    var playbackSpeed: Float
    var loopEnabled: Bool
    var showSkeleton: Bool
    var debugMode: SkinningDebugMode
    var selectedBoneIndex: Int32
    var boneCount: Int32
    var bone1RotationDegrees: Float

    static let empty = SkinningLabSnapshot(
        selectedObjectID: nil,
        selectedObjectName: nil,
        isSelectedObjectSkinned: false,
        skinningEnabled: false,
        isPlaying: false,
        playbackTime: 0.0,
        playbackSpeed: 1.0,
        loopEnabled: true,
        showSkeleton: false,
        debugMode: .none,
        selectedBoneIndex: 0,
        boneCount: 0,
        bone1RotationDegrees: 0.0
    )
}

enum SkinningDebugMode: Int32, CaseIterable, Codable {
    case none = 0
    case dominantBone = 1
    case selectedBoneWeight = 2
    case weightSumCheck = 3
    case indexValidity = 4

    var displayName: String {
        switch self {
        case .none: return "None"
        case .dominantBone: return "Dominant Bone"
        case .selectedBoneWeight: return "Weight Heatmap"
        case .weightSumCheck: return "Weight Sum Check"
        case .indexValidity: return "Index Validity"
        }
    }
}

struct MorphLabSnapshot: Equatable {
    var selectedObjectID: UInt32?
    var selectedObjectName: String?
    var isSelectedObjectMorphed: Bool
    var morphEnabled: Bool
    var isPlaying: Bool
    var playbackTime: Float
    var playbackSpeed: Float
    var loopEnabled: Bool
    var targetWeights: [Float]
    var targetCount: Int32
    var debugMode: MorphDebugMode
    var selectedTargetIndex: Int32

    static let empty = MorphLabSnapshot(
        selectedObjectID: nil,
        selectedObjectName: nil,
        isSelectedObjectMorphed: false,
        morphEnabled: false,
        isPlaying: false,
        playbackTime: 0.0,
        playbackSpeed: 1.0,
        loopEnabled: true,
        targetWeights: [],
        targetCount: 0,
        debugMode: .none,
        selectedTargetIndex: 0
    )
}

enum MorphLabLimits {
    static let maxTargets: Int = 8
}

enum MorphDebugMode: Int32, CaseIterable, Codable {
    case none = 0
    case displacement = 1
    case selectedTargetDelta = 2
    case outlier = 3

    var displayName: String {
        switch self {
        case .none: return "None"
        case .displacement: return "Displacement"
        case .selectedTargetDelta: return "Target Delta"
        case .outlier: return "Outlier"
        }
    }
}
