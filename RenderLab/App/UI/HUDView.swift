//
//  HUDView.swift
//  RenderLab
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//  SwiftUI overlay rendering FPS/mode text and diagnostics readouts.
//

import SwiftUI

struct HUDView: View {
    @ObservedObject var hud: HUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RenderLab")
                .font(.headline)
            Text(hud.fpsText)
                .font(.system(.body, design: .monospaced))
            Text(hud.msText)
                .font(.system(.body, design: .monospaced))
            Text(hud.modeText)
                .font(.system(.body, design: .monospaced))
            ForEach(hud.diagnosticsLines, id: \.self) { line in
                Text(line)
                    .font(.system(.footnote, design: .monospaced))
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}
