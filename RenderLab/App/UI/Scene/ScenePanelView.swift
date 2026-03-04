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

                        if settings.showModelMatrixDebug {
                            modelMatrixDebug(transform: selectedObject.transform)
                        }
                    } else {
                        Text("No object selected")
                            .foregroundStyle(.secondary)
                        gizmoControls
                        debugControls
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
        .onReceive(scenePanel.$objects) { _ in
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
            Toggle("Show Model Matrix", isOn: $settings.showModelMatrixDebug)
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
        scenePanel.setLocalTransform(objectID: object.id, transform: draftTransform)
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
}
