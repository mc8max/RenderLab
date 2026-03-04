//
//  ContentView.swift
//  RenderLab
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//

import SwiftUI


struct ContentView: View {
    @StateObject private var hud = HUDModel()
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

            ZStack(alignment: .topLeading) {
                MetalView(
                    hud: hud,
                    settings: settings,
                    sceneSink: scenePanel,
                    sceneCommands: sceneCommands
                )
                    .ignoresSafeArea()

                if settings.showHUD {
                    HUDView(hud: hud)
                        .padding(10)
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 650)
    }
}
