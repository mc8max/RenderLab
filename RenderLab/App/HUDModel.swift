//
//  HUDModel.swift
//  RTRBaseline
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//

import Foundation
import Combine

final class HUDModel: ObservableObject {
    @Published private(set) var fpsText: String = "FPS: --"
    @Published private(set) var msText: String = "Frame: -- ms"
    @Published private(set) var modeText: String = "Mode: VertexColor"

    func update(fps: Double, frameMs: Double) {
        fpsText = String(format: "FPS: %.0f", fps)
        msText = String(format: "Frame: %.2f ms", frameMs)
    }
    
    func updateMode(_ name: String) {
        modeText = "Mode: \(name)"
    }
}
