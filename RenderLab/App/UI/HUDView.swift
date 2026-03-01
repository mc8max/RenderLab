//
//  HUDView.swift
//  RTRBaseline
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//

import SwiftUI

struct HUDView: View {
    @ObservedObject var hud: HUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RTRBaseline")
                .font(.headline)
            Text(hud.fpsText)
                .font(.system(.body, design: .monospaced))
            Text(hud.msText)
                .font(.system(.body, design: .monospaced))
            Text(hud.modeText)
                .font(.system(.body, design: .monospaced))
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}
