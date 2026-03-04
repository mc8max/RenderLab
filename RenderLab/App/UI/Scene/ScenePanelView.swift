//
//  ScenePanelView.swift
//  RenderLab
//
//  Sidebar scene list with selection and visibility toggles.
//

import SwiftUI

struct ScenePanelView: View {
    @ObservedObject var scenePanel: ScenePanelModel
    let sceneCommands: SceneCommandBridge

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
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
    }
}
