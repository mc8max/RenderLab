//
//  Renderer+Camera.swift
//  RenderLab
//
//  Camera updates and camera input handling.
//

import MetalKit

extension Renderer {
    func orbit(deltaX: Float, deltaY: Float) {
        var cameraParams = makeCameraParamsSnapshot()
        coreCameraOrbit(&cameraState, deltaX, deltaY, &cameraParams)
    }

    func pan(deltaX: Float, deltaY: Float) {
        var cameraParams = makeCameraParamsSnapshot()
        coreCameraPan(&cameraState, deltaX, deltaY, &cameraParams)
    }

    func zoom(delta: Float) {
        var cameraParams = makeCameraParamsSnapshot()
        coreCameraZoom(&cameraState, delta, &cameraParams)
    }

    /// Update simulation parameters including camera and uniforms.
    func update(dt: Double, view: MTKView) {
        elapsedTime += Float(dt)

        let w = max(1.0, view.drawableSize.width)
        let h = max(1.0, view.drawableSize.height)
        let aspect = Float(w / h)

        var cameraParams = makeCameraParamsSnapshot()
        cameraDebugNear = cameraParams.nearZ
        cameraDebugFar = cameraParams.farZ

        coreCameraSanitize(&cameraState, &cameraParams)
        coreCameraBuildOrbitUniforms(
            &currentUniforms,
            elapsedTime,
            aspect,
            &cameraState,
            &cameraParams
        )

        updateInterpolationLab(deltaSeconds: Float(dt))
        updateSkinningLab(deltaSeconds: Float(dt))
    }

    func makeCameraParamsSnapshot() -> CoreCameraParams {
        let nearZ = max(0.001, settings.cameraNear)
        let farZ = max(settings.cameraFar, nearZ + 0.01)
        let fovYDegrees = min(max(settings.cameraFovYDegrees, 1.0), 170.0)

        var params = baseCameraParams
        params.nearZ = nearZ
        params.farZ = farZ
        params.fovYDegrees = fovYDegrees
        return params
    }
}
