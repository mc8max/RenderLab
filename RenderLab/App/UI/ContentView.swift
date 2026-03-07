//
//  ContentView.swift
//  RenderLab
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//  Root split-view layout that hosts scene controls and the Metal viewport.
//

import SwiftUI


struct ContentView: View {
    @StateObject private var settings = RenderSettings()
    @StateObject private var scenePanel = ScenePanelModel()
    @State private var sceneCommands = SceneCommandBridge()

    var body: some View {
        HStack(spacing: 0) {
            ScenePanelView(
                scenePanel: scenePanel,
                settings: settings,
                sceneCommands: sceneCommands
            )

            Divider()

            MetalView(
                settings: settings,
                sceneSink: scenePanel,
                sceneCommands: sceneCommands
            )
            .ignoresSafeArea()
        }
        .frame(minWidth: 1000, minHeight: 650)
    }
}
