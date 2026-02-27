//
//  ContentView.swift
//  RTRBaseline
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//

import SwiftUI


struct ContentView: View {
    @StateObject private var hud = HUDModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            MetalView(hud: hud)
                .ignoresSafeArea()

            HUDView(hud: hud)
                .padding(10)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
