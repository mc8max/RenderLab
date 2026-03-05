//
//  Renderer+FrameContext.swift
//  RenderLab
//
//  Frame-level context assembly for render passes.
//

extension Renderer {
    func makeRenderContext() -> RenderContext {
        guard let renderAssets else {
            fatalError("RenderAssets must be initialized before rendering.")
        }
        let frameSettings = FrameSettingsSnapshot(
            depthTest: settings.depthTest,
            cullMode: settings.cullMode,
            debugMode: settings.debugMode,
            showGrid: settings.showGrid,
            showAxis: settings.showAxis,
            showObjectBasis: settings.showObjectBasis,
            showPivot: settings.showPivot,
            transformSpace: settings.transformSpace,
            showModelMatrixDebug: settings.showModelMatrixDebug,
            cameraNear: cameraDebugNear,
            cameraFar: cameraDebugFar,
            clearColorRGBA: settings.clearColorRGBA
        )
        let uniforms = currentUniforms
        let interpolationGhostItems = makeInterpolationGhostDrawItems(baseUniforms: uniforms)

        return RenderContext(
            frameSettings: frameSettings,
            uniforms: uniforms,
            renderAssets: renderAssets,
            scene: scene,
            selectedObjectID: selectedObjectID,
            interpolationGhostItems: interpolationGhostItems
        )
    }
}
