//
//  ScenePanelView.swift
//  RenderLab
//
//  Sidebar scene list with selection and visibility toggles.
//

import SwiftUI
import simd

struct ScenePanelView: View {
    @ObservedObject var scenePanel: ScenePanelModel
    @ObservedObject var settings: RenderSettings
    let sceneCommands: SceneCommandBridge
    @State private var draftTransform: SceneTransform = SceneTransform()
    @State private var draftObjectID: UInt32?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Scene")
                    .font(.headline)
                Spacer()
                Button("Add Cube") {
                    sceneCommands.addCubeObject()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            List(scenePanel.objects) { object in
                HStack(spacing: 10) {
                    Button {
                        let newVisibility = !object.isVisible
                        scenePanel.setLocalVisibility(objectID: object.id, isVisible: newVisibility)
                        sceneCommands.setObjectVisibility(objectID: object.id, isVisible: newVisibility)
                    } label: {
                        Image(systemName: object.isVisible ? "eye" : "eye.slash")
                            .foregroundStyle(object.isVisible ? .primary : .secondary)
                            .frame(width: 18)
                    }
                    .buttonStyle(.plain)

                    Text(object.name)
                        .lineLimit(1)

                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    scenePanel.setLocalSelection(object.id)
                    sceneCommands.selectObject(object.id)
                }
                .listRowBackground(
                    scenePanel.selectedObjectID == object.id
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
                )
            }
            .listStyle(.sidebar)
            .frame(height: objectListHeight)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let selectedObject = scenePanel.selectedObject {
                        Text(selectedObject.name)
                            .font(.headline)
                            .lineLimit(1)

                        transformEditor
                        gizmoControls
                        debugControls
                        interpolationLabPanel
                        morphLabPanel
                        skinningLabPanel

                        if settings.showModelMatrixDebug {
                            modelMatrixDebug(transform: selectedObject.transform)
                        }
                    } else {
                        Text("No object selected")
                            .foregroundStyle(.secondary)
                        gizmoControls
                        debugControls
                        interpolationLabPanel
                        morphLabPanel
                        skinningLabPanel
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .onAppear(perform: syncDraftFromSelection)
        .onChange(of: scenePanel.selectedObjectID) { _, _ in
            syncDraftFromSelection()
        }
        .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)
    }

    private var gizmoControls: some View {
        GroupBox("Gizmos") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Transform Space", selection: $settings.transformSpace) {
                    ForEach(TransformSpace.allCases, id: \.self) { space in
                        Text(space.displayName).tag(space)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Show Axis", isOn: $settings.showAxis)
                Toggle("Show Grid", isOn: $settings.showGrid)
                Toggle("Show Basis Vectors", isOn: $settings.showObjectBasis)
                Toggle("Show Pivot Point", isOn: $settings.showPivot)
            }
        }
    }

    private var debugControls: some View {
        GroupBox("Debug") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show Model Matrix", isOn: $settings.showModelMatrixDebug)
                Toggle(
                    "Suspend UI Sync During Playback",
                    isOn: $settings.suspendUISyncDuringPlayback
                )
                Toggle("Enable Diagnostics Log Dump", isOn: $settings.enableDiagnosticsLogDump)
            }
        }
    }

    private var interpolationLabPanel: some View {
        let snapshot = scenePanel.interpolationLab
        return GroupBox("Interpolation Lab") {
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.selectedObjectName ?? "No object selected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(snapshot.selectedObjectID == nil ? .secondary : .primary)

                HStack(spacing: 6) {
                    Button("Set A") {
                        sceneCommands.setInterpolationKeyframeAFromCurrent()
                    }
                    .disabled(snapshot.selectedObjectID == nil)

                    Button("Set B") {
                        sceneCommands.setInterpolationKeyframeBFromCurrent()
                    }
                    .disabled(snapshot.selectedObjectID == nil)

                    Button("Swap") {
                        sceneCommands.swapInterpolationKeyframes()
                    }
                    .disabled(snapshot.hasKeyframeA == false && snapshot.hasKeyframeB == false)

                    Button("Reset") {
                        sceneCommands.resetInterpolationLab()
                    }
                }

                HStack(spacing: 6) {
                    Button("Apply A") {
                        sceneCommands.applyInterpolationKeyframeA()
                    }
                    .disabled(snapshot.hasKeyframeA == false)

                    Button("Apply B") {
                        sceneCommands.applyInterpolationKeyframeB()
                    }
                    .disabled(snapshot.hasKeyframeB == false)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("t")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.3f", snapshot.t))
                            .font(.system(.caption, design: .monospaced))
                    }
                    Slider(value: interpolationTimeBinding, in: 0...1)
                        .disabled(snapshot.hasKeyframeA == false || snapshot.hasKeyframeB == false)
                }

                HStack(spacing: 8) {
                    Button(snapshot.isPlaying ? "Pause" : "Play") {
                        let nextPlaying = !snapshot.isPlaying
                        scenePanel.setLocalInterpolationPlaying(nextPlaying)
                        sceneCommands.setInterpolationPlaying(nextPlaying)
                    }
                    .disabled(snapshot.hasKeyframeA == false || snapshot.hasKeyframeB == false)

                    Picker("Speed", selection: interpolationSpeedBinding) {
                        Text("0.25x").tag(Float(0.25))
                        Text("1x").tag(Float(1.0))
                        Text("2x").tag(Float(2.0))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Picker("Loop", selection: interpolationLoopModeBinding) {
                    ForEach(InterpolationLoopMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Position", selection: interpolationPositionModeBinding) {
                    ForEach(InterpolationScalarMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("Rotation", selection: interpolationRotationModeBinding) {
                    ForEach(InterpolationRotationMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("Scale", selection: interpolationScaleModeBinding) {
                    ForEach(InterpolationScalarMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Toggle("Shortest Path", isOn: interpolationShortestPathBinding)
                Toggle("Show Ghost A", isOn: interpolationShowGhostABinding)
                Toggle("Show Ghost B", isOn: interpolationShowGhostBBinding)

            }
        }
    }

    private var skinningLabPanel: some View {
        let snapshot = scenePanel.skinningLab
        return GroupBox("Skinning Lab") {
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.selectedObjectName ?? "No object selected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(snapshot.selectedObjectID == nil ? .secondary : .primary)

                Toggle("Skinning Enabled", isOn: skinningEnabledBinding)
                    .disabled(snapshot.isSelectedObjectSkinned == false)

                HStack(spacing: 8) {
                    Button(snapshot.isPlaying ? "Pause" : "Play") {
                        let nextPlaying = !snapshot.isPlaying
                        scenePanel.setLocalSkinningPlaying(nextPlaying)
                        sceneCommands.setSkinningPlaying(nextPlaying)
                    }
                    .disabled(snapshot.isSelectedObjectSkinned == false)

                    Picker("Speed", selection: skinningSpeedBinding) {
                        Text("0.5x").tag(Float(0.5))
                        Text("1x").tag(Float(1.0))
                        Text("2x").tag(Float(2.0))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(snapshot.isSelectedObjectSkinned == false)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Clip Time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.3f", snapshot.playbackTime))
                            .font(.system(.caption, design: .monospaced))
                    }
                    Slider(value: skinningTimeBinding, in: 0...1)
                        .disabled(snapshot.isSelectedObjectSkinned == false)
                }

                Toggle("Loop", isOn: skinningLoopBinding)
                    .disabled(snapshot.isSelectedObjectSkinned == false)

                Toggle("Show Skeleton", isOn: skinningShowSkeletonBinding)
                    .disabled(snapshot.isSelectedObjectSkinned == false)

                Picker("Debug Mode", selection: skinningDebugModeBinding) {
                    ForEach(SkinningDebugMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .disabled(snapshot.isSelectedObjectSkinned == false)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Bone1 Z (deg)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f", snapshot.bone1RotationDegrees))
                            .font(.system(.caption, design: .monospaced))
                    }
                    Slider(value: skinningBone1RotationBinding, in: -120...120)
                        .disabled(snapshot.isSelectedObjectSkinned == false || snapshot.isPlaying)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Debug Bone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(snapshot.selectedBoneIndex)")
                            .font(.system(.caption, design: .monospaced))
                    }
                    let debugBoneSliderUpperBound = max(1, snapshot.boneCount - 1)
                    Slider(
                        value: skinningSelectedBoneBinding,
                        in: 0...Double(debugBoneSliderUpperBound),
                        step: 1
                    )
                    .disabled(snapshot.isSelectedObjectSkinned == false || snapshot.boneCount <= 1)
                }

                Text("Bone Count: \(snapshot.boneCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if snapshot.isSelectedObjectSkinned == false {
                    Text("Select a skinned mesh object to control skinning.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var morphLabPanel: some View {
        let snapshot = scenePanel.morphLab
        let activeTargetCount = max(0, Int(snapshot.targetCount))
        return GroupBox("Morph Target Lab") {
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.selectedObjectName ?? "No object selected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(snapshot.selectedObjectID == nil ? .secondary : .primary)

                Toggle("Morph Enabled", isOn: morphEnabledBinding)
                    .disabled(snapshot.isSelectedObjectMorphed == false)

                HStack(spacing: 8) {
                    Button(snapshot.isPlaying ? "Pause" : "Play") {
                        let nextPlaying = !snapshot.isPlaying
                        scenePanel.setLocalMorphPlaying(nextPlaying)
                        sceneCommands.setMorphPlaying(nextPlaying)
                    }
                    .disabled(snapshot.isSelectedObjectMorphed == false || activeTargetCount == 0)

                    Picker("Speed", selection: morphSpeedBinding) {
                        Text("0.5x").tag(Float(0.5))
                        Text("1x").tag(Float(1.0))
                        Text("2x").tag(Float(2.0))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(snapshot.isSelectedObjectMorphed == false || activeTargetCount == 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Playback Time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.3f", snapshot.playbackTime))
                            .font(.system(.caption, design: .monospaced))
                    }
                    Slider(value: morphTimeBinding, in: 0...1)
                        .disabled(snapshot.isSelectedObjectMorphed == false || activeTargetCount == 0)
                }

                Toggle("Loop", isOn: morphLoopBinding)
                    .disabled(snapshot.isSelectedObjectMorphed == false || activeTargetCount == 0)

                ForEach(0..<activeTargetCount, id: \.self) { targetIndex in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Target \(targetIndex)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(
                                String(
                                    format: "%.3f",
                                    snapshot.targetWeights.indices.contains(targetIndex)
                                        ? snapshot.targetWeights[targetIndex] : 0.0
                                )
                            )
                            .font(.system(.caption, design: .monospaced))
                        }
                        Slider(value: morphTargetWeightBinding(index: targetIndex), in: 0...1)
                            .disabled(snapshot.isSelectedObjectMorphed == false)
                    }
                }

                Picker("Debug Mode", selection: morphDebugModeBinding) {
                    ForEach(MorphDebugMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .disabled(snapshot.isSelectedObjectMorphed == false)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Debug Target")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(snapshot.selectedTargetIndex)")
                            .font(.system(.caption, design: .monospaced))
                    }
                    let debugTargetUpperBound = max(1, activeTargetCount - 1)
                    Slider(
                        value: morphSelectedTargetBinding,
                        in: 0...Double(debugTargetUpperBound),
                        step: 1
                    )
                    .disabled(snapshot.isSelectedObjectMorphed == false || activeTargetCount <= 1)
                }

                HStack(spacing: 8) {
                    Button("Reset Weights") {
                        scenePanel.resetLocalMorphWeights()
                        sceneCommands.resetMorphWeights()
                    }
                    .disabled(snapshot.isSelectedObjectMorphed == false || activeTargetCount == 0)
                }

                Text("Target Count: \(snapshot.targetCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if snapshot.isSelectedObjectMorphed == false {
                    Text("Select a morph-enabled mesh object to control morphing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if activeTargetCount == 0 {
                    Text("Selected object has no valid morph targets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var transformEditor: some View {
        GroupBox("Transform (TRS)") {
            VStack(alignment: .leading, spacing: 8) {
                vectorEditorRow(
                    title: "Position",
                    x: positionBinding(\.x),
                    y: positionBinding(\.y),
                    z: positionBinding(\.z)
                )
                vectorEditorRow(
                    title: "Rotation (deg)",
                    x: rotationBinding(\.x),
                    y: rotationBinding(\.y),
                    z: rotationBinding(\.z)
                )
                vectorEditorRow(
                    title: "Scale",
                    x: scaleBinding(\.x),
                    y: scaleBinding(\.y),
                    z: scaleBinding(\.z)
                )
            }
        }
        .disabled(scenePanel.interpolationLab.isPlaying)
    }

    private func vectorEditorRow(
        title: String,
        x: Binding<Double>,
        y: Binding<Double>,
        z: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                axisField(name: "X", value: x)
                axisField(name: "Y", value: y)
                axisField(name: "Z", value: z)
            }
        }
    }

    private func axisField(name: String, value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 10, alignment: .leading)
            TextField(
                name,
                value: value,
                format: .number.precision(.fractionLength(3))
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
        }
    }

    private func modelMatrixDebug(transform: SceneTransform) -> some View {
        let matrix = transform.modelMatrix()
        let pivot = transform.pivotPoint()

        return GroupBox("Model Matrix / Pivot") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(0..<4, id: \.self) { row in
                    Text(matrixRowText(matrix, row: row))
                        .font(.system(.caption, design: .monospaced))
                }
                Text("Cols")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(0..<4, id: \.self) { column in
                    Text(matrixColumnText(matrix, column: column))
                        .font(.system(.caption, design: .monospaced))
                }
                Text(
                    String(
                        format: "Pivot: (%.3f, %.3f, %.3f)",
                        pivot.x,
                        pivot.y,
                        pivot.z
                    )
                )
                .font(.system(.caption, design: .monospaced))
                .padding(.top, 4)
            }
        }
    }

    private var interpolationTimeBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(scenePanel.interpolationLab.t) },
            set: { newValue in
                let clamped = min(max(Float(newValue), 0.0), 1.0)
                scenePanel.setLocalInterpolationTime(clamped)
                sceneCommands.setInterpolationTime(clamped)
            }
        )
    }

    private var interpolationSpeedBinding: Binding<Float> {
        Binding<Float>(
            get: { scenePanel.interpolationLab.speed },
            set: { newValue in
                let speed = max(0.0, newValue)
                scenePanel.setLocalInterpolationSpeed(speed)
                sceneCommands.setInterpolationSpeed(speed)
            }
        )
    }

    private var interpolationLoopModeBinding: Binding<InterpolationLoopMode> {
        Binding<InterpolationLoopMode>(
            get: { scenePanel.interpolationLab.loopMode },
            set: { newValue in
                scenePanel.setLocalInterpolationLoopMode(newValue)
                sceneCommands.setInterpolationLoopMode(newValue)
            }
        )
    }

    private var interpolationPositionModeBinding: Binding<InterpolationScalarMode> {
        Binding<InterpolationScalarMode>(
            get: { scenePanel.interpolationLab.positionMode },
            set: { newValue in
                scenePanel.setLocalInterpolationPositionMode(newValue)
                sceneCommands.setInterpolationPositionMode(newValue)
            }
        )
    }

    private var interpolationRotationModeBinding: Binding<InterpolationRotationMode> {
        Binding<InterpolationRotationMode>(
            get: { scenePanel.interpolationLab.rotationMode },
            set: { newValue in
                scenePanel.setLocalInterpolationRotationMode(newValue)
                sceneCommands.setInterpolationRotationMode(newValue)
            }
        )
    }

    private var interpolationScaleModeBinding: Binding<InterpolationScalarMode> {
        Binding<InterpolationScalarMode>(
            get: { scenePanel.interpolationLab.scaleMode },
            set: { newValue in
                scenePanel.setLocalInterpolationScaleMode(newValue)
                sceneCommands.setInterpolationScaleMode(newValue)
            }
        )
    }

    private var interpolationShortestPathBinding: Binding<Bool> {
        Binding<Bool>(
            get: { scenePanel.interpolationLab.shortestPath },
            set: { newValue in
                scenePanel.setLocalInterpolationShortestPath(newValue)
                sceneCommands.setInterpolationShortestPath(newValue)
            }
        )
    }

    private var interpolationShowGhostABinding: Binding<Bool> {
        Binding<Bool>(
            get: { scenePanel.interpolationLab.showGhostA },
            set: { newValue in
                scenePanel.setLocalInterpolationShowGhostA(newValue)
                sceneCommands.setInterpolationShowGhostA(newValue)
            }
        )
    }

    private var interpolationShowGhostBBinding: Binding<Bool> {
        Binding<Bool>(
            get: { scenePanel.interpolationLab.showGhostB },
            set: { newValue in
                scenePanel.setLocalInterpolationShowGhostB(newValue)
                sceneCommands.setInterpolationShowGhostB(newValue)
            }
        )
    }

    private var skinningEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { scenePanel.skinningLab.skinningEnabled },
            set: { newValue in
                scenePanel.setLocalSkinningEnabled(newValue)
                sceneCommands.setSkinningEnabled(newValue)
            }
        )
    }

    private var skinningBone1RotationBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(scenePanel.skinningLab.bone1RotationDegrees) },
            set: { newValue in
                let clamped = min(max(Float(newValue), -180.0), 180.0)
                scenePanel.setLocalSkinningBone1RotationDegrees(clamped)
                sceneCommands.setSkinningBone1RotationDegrees(clamped)
            }
        )
    }

    private var skinningTimeBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(scenePanel.skinningLab.playbackTime) },
            set: { newValue in
                let clamped = min(max(Float(newValue), 0.0), 1.0)
                scenePanel.setLocalSkinningTime(clamped)
                sceneCommands.setSkinningTime(clamped)
            }
        )
    }

    private var skinningSpeedBinding: Binding<Float> {
        Binding<Float>(
            get: { scenePanel.skinningLab.playbackSpeed },
            set: { newValue in
                let clamped = max(0.0, newValue)
                scenePanel.setLocalSkinningSpeed(clamped)
                sceneCommands.setSkinningSpeed(clamped)
            }
        )
    }

    private var skinningLoopBinding: Binding<Bool> {
        Binding<Bool>(
            get: { scenePanel.skinningLab.loopEnabled },
            set: { newValue in
                scenePanel.setLocalSkinningLoopEnabled(newValue)
                sceneCommands.setSkinningLoopEnabled(newValue)
            }
        )
    }

    private var skinningShowSkeletonBinding: Binding<Bool> {
        Binding<Bool>(
            get: { scenePanel.skinningLab.showSkeleton },
            set: { newValue in
                scenePanel.setLocalSkinningShowSkeleton(newValue)
                sceneCommands.setSkinningShowSkeleton(newValue)
            }
        )
    }

    private var skinningDebugModeBinding: Binding<SkinningDebugMode> {
        Binding<SkinningDebugMode>(
            get: { scenePanel.skinningLab.debugMode },
            set: { newValue in
                scenePanel.setLocalSkinningDebugMode(newValue)
                sceneCommands.setSkinningDebugMode(newValue)
            }
        )
    }

    private var skinningSelectedBoneBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(scenePanel.skinningLab.selectedBoneIndex) },
            set: { newValue in
                let clamped = max(0, Int32(newValue.rounded()))
                scenePanel.setLocalSkinningSelectedBoneIndex(clamped)
                sceneCommands.setSkinningSelectedBoneIndex(clamped)
            }
        )
    }

    private var morphEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { scenePanel.morphLab.morphEnabled },
            set: { newValue in
                scenePanel.setLocalMorphEnabled(newValue)
                sceneCommands.setMorphEnabled(newValue)
            }
        )
    }

    private var morphTimeBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(scenePanel.morphLab.playbackTime) },
            set: { newValue in
                let clamped = min(max(Float(newValue), 0.0), 1.0)
                scenePanel.setLocalMorphTime(clamped)
                sceneCommands.setMorphTime(clamped)
            }
        )
    }

    private var morphSpeedBinding: Binding<Float> {
        Binding<Float>(
            get: { scenePanel.morphLab.playbackSpeed },
            set: { newValue in
                let clamped = max(0.0, newValue)
                scenePanel.setLocalMorphSpeed(clamped)
                sceneCommands.setMorphSpeed(clamped)
            }
        )
    }

    private var morphLoopBinding: Binding<Bool> {
        Binding<Bool>(
            get: { scenePanel.morphLab.loopEnabled },
            set: { newValue in
                scenePanel.setLocalMorphLoopEnabled(newValue)
                sceneCommands.setMorphLoopEnabled(newValue)
            }
        )
    }

    private var morphDebugModeBinding: Binding<MorphDebugMode> {
        Binding<MorphDebugMode>(
            get: { scenePanel.morphLab.debugMode },
            set: { newValue in
                scenePanel.setLocalMorphDebugMode(newValue)
                sceneCommands.setMorphDebugMode(newValue)
            }
        )
    }

    private var morphSelectedTargetBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(scenePanel.morphLab.selectedTargetIndex) },
            set: { newValue in
                let clamped = max(0, Int32(newValue.rounded()))
                scenePanel.setLocalMorphSelectedTargetIndex(clamped)
                sceneCommands.setMorphSelectedTargetIndex(clamped)
            }
        )
    }

    private func morphTargetWeightBinding(index: Int) -> Binding<Double> {
        Binding<Double>(
            get: {
                guard scenePanel.morphLab.targetWeights.indices.contains(index) else { return 0.0 }
                return Double(scenePanel.morphLab.targetWeights[index])
            },
            set: { newValue in
                let clamped = min(max(Float(newValue), 0.0), 1.0)
                scenePanel.setLocalMorphTargetWeight(index: index, weight: clamped)
                if index == 0 {
                    scenePanel.setLocalMorphTime(clamped)
                }
                sceneCommands.setMorphTargetWeight(index: Int32(index), weight: clamped)
            }
        )
    }

    private func positionBinding(_ axis: WritableKeyPath<SIMD3<Float>, Float>) -> Binding<Double> {
        Binding<Double>(
            get: { Double(draftTransform.position[keyPath: axis]) },
            set: { newValue in
                draftTransform.position[keyPath: axis] = Float(newValue)
                commitDraftTransformIfNeeded()
            }
        )
    }

    private func rotationBinding(_ axis: WritableKeyPath<SIMD3<Float>, Float>) -> Binding<Double> {
        Binding<Double>(
            get: { Double(draftTransform.rotation[keyPath: axis] * 180.0 / .pi) },
            set: { newValue in
                draftTransform.rotation[keyPath: axis] = Float(newValue) * .pi / 180.0
                commitDraftTransformIfNeeded()
            }
        )
    }

    private func scaleBinding(_ axis: WritableKeyPath<SIMD3<Float>, Float>) -> Binding<Double> {
        Binding<Double>(
            get: { Double(draftTransform.scale[keyPath: axis]) },
            set: { newValue in
                draftTransform.scale[keyPath: axis] = max(0.0001, Float(newValue))
                commitDraftTransformIfNeeded()
            }
        )
    }

    private func commitDraftTransformIfNeeded() {
        guard let object = scenePanel.selectedObject else { return }
        guard draftTransform.isApproximatelyEqual(to: object.transform) == false else { return }
        sceneCommands.setObjectTransform(objectID: object.id, transform: draftTransform)
    }

    private func syncDraftFromSelection() {
        guard let object = scenePanel.selectedObject else {
            draftObjectID = nil
            draftTransform = SceneTransform()
            return
        }

        let selectionChanged = draftObjectID != object.id
        let transformChanged = draftTransform.isApproximatelyEqual(to: object.transform) == false
        guard selectionChanged || transformChanged else { return }

        draftObjectID = object.id
        draftTransform = object.transform
    }

    private func matrixRowText(_ matrix: simd_float4x4, row: Int) -> String {
        String(
            format: "[% .3f % .3f % .3f % .3f]",
            matrix.columns.0[row],
            matrix.columns.1[row],
            matrix.columns.2[row],
            matrix.columns.3[row]
        )
    }

    private func matrixColumnText(_ matrix: simd_float4x4, column: Int) -> String {
        let col: SIMD4<Float>
        switch column {
        case 0: col = matrix.columns.0
        case 1: col = matrix.columns.1
        case 2: col = matrix.columns.2
        case 3: col = matrix.columns.3
        default: col = SIMD4<Float>(repeating: 0)
        }
        return String(
            format: "[% .3f % .3f % .3f % .3f]",
            col.x,
            col.y,
            col.z,
            col.w
        )
    }

    private var objectListHeight: CGFloat {
        min(160, max(96, CGFloat(scenePanel.objects.count) * 28.0 + 8.0))
    }

}
