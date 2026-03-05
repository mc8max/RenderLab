//
//  Renderer+HUD.swift
//  RenderLab
//
//  HUD updates and UI toggle controls.
//

import Foundation
import AppKit
import MetalKit
import QuartzCore

private struct HUDDiagnosticsSnapshot {
    var avgUpdateMs: Double
    var avgRenderMs: Double
    var avgFrameGapMs: Double
    var maxFrameGapMs: Double
    var frameGapOver33PerSecond: Double
    var frameGapOver100PerSecond: Double
    var avgPassMs: [(name: String, ms: Double)]
    var avgCommandBufferLatencyMs: Double
    var avgMainQueueLatencyMs: Double
    var maxMainQueueLatencyMs: Double
    var mainQueueLatencyOver16PerSecond: Double
    var mainQueueLatencyOver33PerSecond: Double
    var inFlightCommandBuffers: Int
    var peakInFlightCommandBuffers: Int
    var sceneSnapshotPublishesPerSecond: Double
    var selectedTransformPublishesPerSecond: Double
    var interpolationPublishesPerSecond: Double
}

private struct DiagnosticsDumpSnapshot {
    var windowSeconds: Double
    var frames: Int
    var avgFPS: Double
    var avgFrameMs: Double
    var avgUpdateMs: Double
    var avgRenderMs: Double
    var avgFrameGapMs: Double
    var maxFrameGapMs: Double
    var frameGapOver33PerSecond: Double
    var frameGapOver100PerSecond: Double
    var avgPassMs: [(name: String, ms: Double)]
    var avgCommandBufferLatencyMs: Double
    var avgMainQueueLatencyMs: Double
    var maxMainQueueLatencyMs: Double
    var mainQueueLatencyOver16PerSecond: Double
    var mainQueueLatencyOver33PerSecond: Double
    var inFlightCommandBuffers: Int
    var peakInFlightCommandBuffers: Int
    var sceneSnapshotPublishesPerSecond: Double
    var selectedTransformPublishesPerSecond: Double
    var interpolationPublishesPerSecond: Double
    var runtimeState: RuntimeStateSnapshot
}

private struct RuntimeStateSnapshot {
    var appIsActive: Bool
    var windowIsVisible: Bool?
    var windowIsOccluded: Bool?
    var thermalState: String
    var lowPowerModeEnabled: Bool
    var viewIsPaused: Bool?
    var viewEnableSetNeedsDisplay: Bool?
    var preferredFramesPerSecond: Int?
    var suspendUISyncDuringPlayback: Bool
}

extension Renderer {
    /// Update the HUD with current frame timing information.
    func updateHUD(dt: Double) {
        updateDiagnosticsDump(dt: dt)
        hudAccumulatedTime += dt
        hudAccumulatedFrameTime += dt
        hudAccumulatedFrames += 1

        guard hudAccumulatedTime >= hudUpdateInterval, hudAccumulatedFrames > 0 else {
            return
        }

        let sampleWindowSeconds = hudAccumulatedFrameTime
        let avgDt = sampleWindowSeconds / Double(hudAccumulatedFrames)
        let fps = 1.0 / avgDt
        let ms = avgDt * 1000.0
        let diagnostics = consumeHUDDiagnostics(sampleWindowSeconds: sampleWindowSeconds)
        let diagnosticsLines = makeHUDDiagnosticsLines(snapshot: diagnostics)
        let suppressHUDUpdates = shouldSuspendUISyncForBackgroundState()

        hudAccumulatedTime.formTruncatingRemainder(dividingBy: hudUpdateInterval)
        hudAccumulatedFrameTime = 0.0
        hudAccumulatedFrames = 0

        guard suppressHUDUpdates == false else { return }
        DispatchQueue.main.async { [weak hud] in
            hud?.update(fps: fps, frameMs: ms)
            hud?.updateDiagnostics(lines: diagnosticsLines)
        }
    }

    func recordFrameDiagnostics(
        updateMs: Double,
        renderMs: Double,
        frameGapMs: Double,
        passDurationsMs: [String: Double]
    ) {
        diagnosticsLock.lock()
        diagnosticsUpdateMsAccum += updateMs
        diagnosticsRenderMsAccum += renderMs
        diagnosticsFrameGapMsAccum += frameGapMs
        diagnosticsFrameGapMaxMs = max(diagnosticsFrameGapMaxMs, frameGapMs)
        if frameGapMs >= 33.0 {
            diagnosticsFrameGapOver33Count += 1
        }
        if frameGapMs >= 100.0 {
            diagnosticsFrameGapOver100Count += 1
        }
        diagnosticsFrameSamples += 1
        diagnosticsDumpUpdateMsAccum += updateMs
        diagnosticsDumpRenderMsAccum += renderMs
        diagnosticsDumpFrameGapMsAccum += frameGapMs
        diagnosticsDumpFrameGapMaxMs = max(diagnosticsDumpFrameGapMaxMs, frameGapMs)
        if frameGapMs >= 33.0 {
            diagnosticsDumpFrameGapOver33Count += 1
        }
        if frameGapMs >= 100.0 {
            diagnosticsDumpFrameGapOver100Count += 1
        }
        for (name, ms) in passDurationsMs {
            diagnosticsPassMsAccum[name, default: 0.0] += ms
            if diagnosticsPassOrder.contains(name) == false {
                diagnosticsPassOrder.append(name)
            }
            diagnosticsDumpPassMsAccum[name, default: 0.0] += ms
            if diagnosticsDumpPassOrder.contains(name) == false {
                diagnosticsDumpPassOrder.append(name)
            }
        }
        diagnosticsLock.unlock()
    }

    func recordMainQueueLatency(latencyMs: Double) {
        diagnosticsLock.lock()
        diagnosticsMainQueueLatencyMsAccum += latencyMs
        diagnosticsMainQueueLatencySamples += 1
        diagnosticsMainQueueLatencyMaxMs = max(diagnosticsMainQueueLatencyMaxMs, latencyMs)
        if latencyMs >= 16.0 {
            diagnosticsMainQueueLatencyOver16Count += 1
        }
        if latencyMs >= 33.0 {
            diagnosticsMainQueueLatencyOver33Count += 1
        }

        diagnosticsDumpMainQueueLatencyMsAccum += latencyMs
        diagnosticsDumpMainQueueLatencySamples += 1
        diagnosticsDumpMainQueueLatencyMaxMs = max(diagnosticsDumpMainQueueLatencyMaxMs, latencyMs)
        if latencyMs >= 16.0 {
            diagnosticsDumpMainQueueLatencyOver16Count += 1
        }
        if latencyMs >= 33.0 {
            diagnosticsDumpMainQueueLatencyOver33Count += 1
        }
        diagnosticsLock.unlock()
    }

    func recordCommandBufferCommitted() {
        diagnosticsLock.lock()
        diagnosticsInFlightCommandBuffers += 1
        diagnosticsPeakInFlightCommandBuffers = max(
            diagnosticsPeakInFlightCommandBuffers,
            diagnosticsInFlightCommandBuffers
        )
        diagnosticsDumpPeakInFlightCommandBuffers = max(
            diagnosticsDumpPeakInFlightCommandBuffers,
            diagnosticsInFlightCommandBuffers
        )
        diagnosticsLock.unlock()
    }

    func recordCommandBufferCompleted(committedAt commitTime: Double) {
        let latencyMs = max(0.0, (CACurrentMediaTime() - commitTime) * 1000.0)
        diagnosticsLock.lock()
        diagnosticsCommandBufferLatencyMsAccum += latencyMs
        diagnosticsCommandBufferLatencySamples += 1
        diagnosticsDumpCommandBufferLatencyMsAccum += latencyMs
        diagnosticsDumpCommandBufferLatencySamples += 1
        diagnosticsInFlightCommandBuffers = max(0, diagnosticsInFlightCommandBuffers - 1)
        diagnosticsLock.unlock()
    }

    func recordSceneSnapshotPublish() {
        diagnosticsLock.lock()
        diagnosticsSceneSnapshotPublishes += 1
        diagnosticsDumpSceneSnapshotPublishes += 1
        diagnosticsLock.unlock()
    }

    func recordSelectedTransformPublish() {
        diagnosticsLock.lock()
        diagnosticsSelectedTransformPublishes += 1
        diagnosticsDumpSelectedTransformPublishes += 1
        diagnosticsLock.unlock()
    }

    func recordInterpolationSnapshotPublish() {
        diagnosticsLock.lock()
        diagnosticsInterpolationPublishes += 1
        diagnosticsDumpInterpolationPublishes += 1
        diagnosticsLock.unlock()
    }

    private func updateDiagnosticsDump(dt: Double) {
        let runtimeState = readRuntimeStateSnapshot()
        let snapshot: DiagnosticsDumpSnapshot? = {
            diagnosticsLock.lock()
            diagnosticsDumpAccumulatedTime += dt
            diagnosticsDumpFrameTime += dt
            diagnosticsDumpFrames += 1

            guard diagnosticsDumpAccumulatedTime >= diagnosticsDumpInterval, diagnosticsDumpFrames > 0 else {
                diagnosticsLock.unlock()
                return nil
            }

            let windowSeconds = max(diagnosticsDumpFrameTime, 0.0001)
            let frames = diagnosticsDumpFrames
            let avgFPS = Double(frames) / windowSeconds
            let avgFrameMs = (windowSeconds / Double(frames)) * 1000.0
            let avgUpdateMs = diagnosticsDumpUpdateMsAccum / Double(frames)
            let avgRenderMs = diagnosticsDumpRenderMsAccum / Double(frames)
            let avgFrameGapMs = diagnosticsDumpFrameGapMsAccum / Double(frames)
            let maxFrameGapMs = diagnosticsDumpFrameGapMaxMs
            let frameGapOver33PerSecond = Double(diagnosticsDumpFrameGapOver33Count) / windowSeconds
            let frameGapOver100PerSecond = Double(diagnosticsDumpFrameGapOver100Count) / windowSeconds
            let passOrder = diagnosticsDumpPassOrder
            let passMap = diagnosticsDumpPassMsAccum
            let avgCommandBufferLatencyMs: Double
            if diagnosticsDumpCommandBufferLatencySamples > 0 {
                avgCommandBufferLatencyMs = diagnosticsDumpCommandBufferLatencyMsAccum
                    / Double(diagnosticsDumpCommandBufferLatencySamples)
            } else {
                avgCommandBufferLatencyMs = 0.0
            }
            let avgMainQueueLatencyMs: Double
            if diagnosticsDumpMainQueueLatencySamples > 0 {
                avgMainQueueLatencyMs = diagnosticsDumpMainQueueLatencyMsAccum
                    / Double(diagnosticsDumpMainQueueLatencySamples)
            } else {
                avgMainQueueLatencyMs = 0.0
            }
            let maxMainQueueLatencyMs = diagnosticsDumpMainQueueLatencyMaxMs
            let mainQueueLatencyOver16PerSecond = Double(diagnosticsDumpMainQueueLatencyOver16Count) / windowSeconds
            let mainQueueLatencyOver33PerSecond = Double(diagnosticsDumpMainQueueLatencyOver33Count) / windowSeconds
            let inFlight = diagnosticsInFlightCommandBuffers
            let peakInFlight = diagnosticsDumpPeakInFlightCommandBuffers
            let scenePerSecond = Double(diagnosticsDumpSceneSnapshotPublishes) / windowSeconds
            let selectedPerSecond = Double(diagnosticsDumpSelectedTransformPublishes) / windowSeconds
            let interpolationPerSecond = Double(diagnosticsDumpInterpolationPublishes) / windowSeconds

            diagnosticsDumpAccumulatedTime.formTruncatingRemainder(dividingBy: diagnosticsDumpInterval)
            diagnosticsDumpFrameTime = 0.0
            diagnosticsDumpFrames = 0
            diagnosticsDumpUpdateMsAccum = 0.0
            diagnosticsDumpRenderMsAccum = 0.0
            diagnosticsDumpFrameGapMsAccum = 0.0
            diagnosticsDumpFrameGapMaxMs = 0.0
            diagnosticsDumpFrameGapOver33Count = 0
            diagnosticsDumpFrameGapOver100Count = 0
            diagnosticsDumpPassMsAccum.removeAll(keepingCapacity: true)
            diagnosticsDumpPassOrder.removeAll(keepingCapacity: true)
            diagnosticsDumpCommandBufferLatencyMsAccum = 0.0
            diagnosticsDumpCommandBufferLatencySamples = 0
            diagnosticsDumpMainQueueLatencyMsAccum = 0.0
            diagnosticsDumpMainQueueLatencySamples = 0
            diagnosticsDumpMainQueueLatencyMaxMs = 0.0
            diagnosticsDumpMainQueueLatencyOver16Count = 0
            diagnosticsDumpMainQueueLatencyOver33Count = 0
            diagnosticsDumpPeakInFlightCommandBuffers = inFlight
            diagnosticsDumpSceneSnapshotPublishes = 0
            diagnosticsDumpSelectedTransformPublishes = 0
            diagnosticsDumpInterpolationPublishes = 0
            diagnosticsLock.unlock()

            let avgPassMs = passOrder.compactMap { name -> (name: String, ms: Double)? in
                guard let sumMs = passMap[name] else { return nil }
                return (name: name, ms: sumMs / Double(frames))
            }

            return DiagnosticsDumpSnapshot(
                windowSeconds: windowSeconds,
                frames: frames,
                avgFPS: avgFPS,
                avgFrameMs: avgFrameMs,
                avgUpdateMs: avgUpdateMs,
                avgRenderMs: avgRenderMs,
                avgFrameGapMs: avgFrameGapMs,
                maxFrameGapMs: maxFrameGapMs,
                frameGapOver33PerSecond: frameGapOver33PerSecond,
                frameGapOver100PerSecond: frameGapOver100PerSecond,
                avgPassMs: avgPassMs,
                avgCommandBufferLatencyMs: avgCommandBufferLatencyMs,
                avgMainQueueLatencyMs: avgMainQueueLatencyMs,
                maxMainQueueLatencyMs: maxMainQueueLatencyMs,
                mainQueueLatencyOver16PerSecond: mainQueueLatencyOver16PerSecond,
                mainQueueLatencyOver33PerSecond: mainQueueLatencyOver33PerSecond,
                inFlightCommandBuffers: inFlight,
                peakInFlightCommandBuffers: peakInFlight,
                sceneSnapshotPublishesPerSecond: scenePerSecond,
                selectedTransformPublishesPerSecond: selectedPerSecond,
                interpolationPublishesPerSecond: interpolationPerSecond,
                runtimeState: runtimeState
            )
        }()

        guard let snapshot else { return }
        dumpDiagnosticsToLog(snapshot: snapshot)
    }

    private func consumeHUDDiagnostics(sampleWindowSeconds: Double) -> HUDDiagnosticsSnapshot {
        diagnosticsLock.lock()

        let frameSamples = max(1, diagnosticsFrameSamples)
        let avgUpdateMs = diagnosticsUpdateMsAccum / Double(frameSamples)
        let avgRenderMs = diagnosticsRenderMsAccum / Double(frameSamples)
        let avgFrameGapMs = diagnosticsFrameGapMsAccum / Double(frameSamples)
        let maxFrameGapMs = diagnosticsFrameGapMaxMs
        let passOrder = diagnosticsPassOrder
        let passMap = diagnosticsPassMsAccum
        let avgCommandBufferLatencyMs: Double
        if diagnosticsCommandBufferLatencySamples > 0 {
            avgCommandBufferLatencyMs = diagnosticsCommandBufferLatencyMsAccum
                / Double(diagnosticsCommandBufferLatencySamples)
        } else {
            avgCommandBufferLatencyMs = 0.0
        }
        let avgMainQueueLatencyMs: Double
        if diagnosticsMainQueueLatencySamples > 0 {
            avgMainQueueLatencyMs = diagnosticsMainQueueLatencyMsAccum
                / Double(diagnosticsMainQueueLatencySamples)
        } else {
            avgMainQueueLatencyMs = 0.0
        }
        let maxMainQueueLatencyMs = diagnosticsMainQueueLatencyMaxMs

        let window = max(sampleWindowSeconds, 0.0001)
        let frameGapOver33PerSecond = Double(diagnosticsFrameGapOver33Count) / window
        let frameGapOver100PerSecond = Double(diagnosticsFrameGapOver100Count) / window
        let mainQueueLatencyOver16PerSecond = Double(diagnosticsMainQueueLatencyOver16Count) / window
        let mainQueueLatencyOver33PerSecond = Double(diagnosticsMainQueueLatencyOver33Count) / window
        let scenePerSecond = Double(diagnosticsSceneSnapshotPublishes) / window
        let selectedPerSecond = Double(diagnosticsSelectedTransformPublishes) / window
        let interpolationPerSecond = Double(diagnosticsInterpolationPublishes) / window
        let inFlight = diagnosticsInFlightCommandBuffers
        let peakInFlight = diagnosticsPeakInFlightCommandBuffers

        diagnosticsUpdateMsAccum = 0.0
        diagnosticsRenderMsAccum = 0.0
        diagnosticsFrameGapMsAccum = 0.0
        diagnosticsFrameGapMaxMs = 0.0
        diagnosticsFrameGapOver33Count = 0
        diagnosticsFrameGapOver100Count = 0
        diagnosticsFrameSamples = 0
        diagnosticsPassMsAccum.removeAll(keepingCapacity: true)
        diagnosticsPassOrder.removeAll(keepingCapacity: true)
        diagnosticsCommandBufferLatencyMsAccum = 0.0
        diagnosticsCommandBufferLatencySamples = 0
        diagnosticsMainQueueLatencyMsAccum = 0.0
        diagnosticsMainQueueLatencySamples = 0
        diagnosticsMainQueueLatencyMaxMs = 0.0
        diagnosticsMainQueueLatencyOver16Count = 0
        diagnosticsMainQueueLatencyOver33Count = 0
        diagnosticsPeakInFlightCommandBuffers = inFlight
        diagnosticsSceneSnapshotPublishes = 0
        diagnosticsSelectedTransformPublishes = 0
        diagnosticsInterpolationPublishes = 0

        diagnosticsLock.unlock()

        let avgPassMs = passOrder.compactMap { name -> (name: String, ms: Double)? in
            guard let sumMs = passMap[name] else { return nil }
            return (name: name, ms: sumMs / Double(frameSamples))
        }

        return HUDDiagnosticsSnapshot(
            avgUpdateMs: avgUpdateMs,
            avgRenderMs: avgRenderMs,
            avgFrameGapMs: avgFrameGapMs,
            maxFrameGapMs: maxFrameGapMs,
            frameGapOver33PerSecond: frameGapOver33PerSecond,
            frameGapOver100PerSecond: frameGapOver100PerSecond,
            avgPassMs: avgPassMs,
            avgCommandBufferLatencyMs: avgCommandBufferLatencyMs,
            avgMainQueueLatencyMs: avgMainQueueLatencyMs,
            maxMainQueueLatencyMs: maxMainQueueLatencyMs,
            mainQueueLatencyOver16PerSecond: mainQueueLatencyOver16PerSecond,
            mainQueueLatencyOver33PerSecond: mainQueueLatencyOver33PerSecond,
            inFlightCommandBuffers: inFlight,
            peakInFlightCommandBuffers: peakInFlight,
            sceneSnapshotPublishesPerSecond: scenePerSecond,
            selectedTransformPublishesPerSecond: selectedPerSecond,
            interpolationPublishesPerSecond: interpolationPerSecond
        )
    }

    private func makeHUDDiagnosticsLines(snapshot: HUDDiagnosticsSnapshot) -> [String] {
        var lines: [String] = []
        lines.append(
            String(
                format: "CPU(ms): update %.2f | render %.2f | gap %.2f (max %.1f)",
                snapshot.avgUpdateMs,
                snapshot.avgRenderMs,
                snapshot.avgFrameGapMs,
                snapshot.maxFrameGapMs
            )
        )

        if snapshot.avgPassMs.isEmpty {
            lines.append("Pass(ms): --")
        } else {
            let passSummary = snapshot.avgPassMs
                .sorted { $0.ms > $1.ms }
                .map { String(format: "%@ %.2f", $0.name, $0.ms) }
                .joined(separator: ", ")
            lines.append("Pass(ms): \(passSummary)")
        }

        lines.append(
            String(
                format: "GPU(ms): cmd %.2f | inFlight %d (peak %d)",
                snapshot.avgCommandBufferLatencyMs,
                snapshot.inFlightCommandBuffers,
                snapshot.peakInFlightCommandBuffers
            )
        )
        lines.append(
            String(
                format: "MainQ(ms): avg %.2f | max %.1f | >16 %.1f/s | >33 %.1f/s",
                snapshot.avgMainQueueLatencyMs,
                snapshot.maxMainQueueLatencyMs,
                snapshot.mainQueueLatencyOver16PerSecond,
                snapshot.mainQueueLatencyOver33PerSecond
            )
        )
        lines.append(
            String(
                format: "GapSpike(/s): >33 %.1f | >100 %.1f",
                snapshot.frameGapOver33PerSecond,
                snapshot.frameGapOver100PerSecond
            )
        )
        lines.append(
            String(
                format: "Sink(/s): scene %.1f | xform %.1f | interp %.1f",
                snapshot.sceneSnapshotPublishesPerSecond,
                snapshot.selectedTransformPublishesPerSecond,
                snapshot.interpolationPublishesPerSecond
            )
        )
        return lines
    }

    private func dumpDiagnosticsToLog(snapshot: DiagnosticsDumpSnapshot) {
        let passSummary: String
        if snapshot.avgPassMs.isEmpty {
            passSummary = "--"
        } else {
            passSummary = snapshot.avgPassMs
                .sorted { $0.ms > $1.ms }
                .map { String(format: "%@ %.2f", $0.name, $0.ms) }
                .joined(separator: ", ")
        }

        print(
            String(
                format: "[DiagnosticsDump] window=%.2fs frames=%d fps=%.2f frameMs=%.2f",
                snapshot.windowSeconds,
                snapshot.frames,
                snapshot.avgFPS,
                snapshot.avgFrameMs
            )
        )
        print(
            String(
                format: "[DiagnosticsDump] cpuMs update=%.2f render=%.2f gap=%.2f gapMax=%.2f",
                snapshot.avgUpdateMs,
                snapshot.avgRenderMs,
                snapshot.avgFrameGapMs,
                snapshot.maxFrameGapMs
            )
        )
        print("[DiagnosticsDump] passMs \(passSummary)")
        print(
            String(
                format: "[DiagnosticsDump] gpuMs cmd=%.2f inFlight=%d peak=%d",
                snapshot.avgCommandBufferLatencyMs,
                snapshot.inFlightCommandBuffers,
                snapshot.peakInFlightCommandBuffers
            )
        )
        print(
            String(
                format: "[DiagnosticsDump] mainQMs avg=%.2f max=%.2f over16PerSec=%.2f over33PerSec=%.2f",
                snapshot.avgMainQueueLatencyMs,
                snapshot.maxMainQueueLatencyMs,
                snapshot.mainQueueLatencyOver16PerSecond,
                snapshot.mainQueueLatencyOver33PerSecond
            )
        )
        print(
            String(
                format: "[DiagnosticsDump] gapSpikePerSec over33=%.2f over100=%.2f",
                snapshot.frameGapOver33PerSecond,
                snapshot.frameGapOver100PerSecond
            )
        )
        print(
            String(
                format: "[DiagnosticsDump] sinkPerSec scene=%.2f xform=%.2f interp=%.2f",
                snapshot.sceneSnapshotPublishesPerSecond,
                snapshot.selectedTransformPublishesPerSecond,
                snapshot.interpolationPublishesPerSecond
            )
        )
        print(
            String(
                format: "[DiagnosticsDump] appState active=%@ visible=%@ occluded=%@ thermal=%@ lowPower=%@ paused=%@ setNeedsDisplay=%@ preferredFPS=%@",
                boolString(snapshot.runtimeState.appIsActive),
                optionalBoolString(snapshot.runtimeState.windowIsVisible),
                optionalBoolString(snapshot.runtimeState.windowIsOccluded),
                snapshot.runtimeState.thermalState,
                boolString(snapshot.runtimeState.lowPowerModeEnabled),
                optionalBoolString(snapshot.runtimeState.viewIsPaused),
                optionalBoolString(snapshot.runtimeState.viewEnableSetNeedsDisplay),
                optionalIntString(snapshot.runtimeState.preferredFramesPerSecond)
            )
        )
        print(
            String(
                format: "[DiagnosticsDump] playbackSync suspendUISync=%@",
                boolString(snapshot.runtimeState.suspendUISyncDuringPlayback)
            )
        )
    }

    private func readRuntimeStateSnapshot() -> RuntimeStateSnapshot {
        let processInfo = ProcessInfo.processInfo
        let lowPowerModeEnabled: Bool
        if #available(macOS 12.0, *) {
            lowPowerModeEnabled = processInfo.isLowPowerModeEnabled
        } else {
            lowPowerModeEnabled = false
        }
        let thermalState = thermalStateString(processInfo.thermalState)
        let cachedState = readCachedRuntimeState()

        return RuntimeStateSnapshot(
            appIsActive: cachedState.appIsActive,
            windowIsVisible: cachedState.windowIsVisible,
            windowIsOccluded: cachedState.windowIsOccluded,
            thermalState: thermalState,
            lowPowerModeEnabled: lowPowerModeEnabled,
            viewIsPaused: cachedState.viewIsPaused,
            viewEnableSetNeedsDisplay: cachedState.viewEnableSetNeedsDisplay,
            preferredFramesPerSecond: cachedState.preferredFramesPerSecond,
            suspendUISyncDuringPlayback: settings.suspendUISyncDuringPlayback
        )
    }

    private func readCachedRuntimeState() -> (
        appIsActive: Bool,
        windowIsVisible: Bool?,
        windowIsOccluded: Bool?,
        viewIsPaused: Bool?,
        viewEnableSetNeedsDisplay: Bool?,
        preferredFramesPerSecond: Int?
    ) {
        runtimeStateLock.lock()
        let state = (
            appIsActive: cachedAppIsActive,
            windowIsVisible: cachedWindowIsVisible,
            windowIsOccluded: cachedWindowIsOccluded,
            viewIsPaused: cachedViewIsPaused,
            viewEnableSetNeedsDisplay: cachedViewEnableSetNeedsDisplay,
            preferredFramesPerSecond: cachedPreferredFramesPerSecond
        )
        runtimeStateLock.unlock()
        return state
    }

    func refreshCachedRuntimeStateOnMain(view: MTKView?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self, weak view] in
                self?.refreshCachedRuntimeStateOnMain(view: view)
            }
            return
        }

        let appIsActive = NSApplication.shared.isActive
        let window = view?.window
        let windowIsVisible = window.map { $0.occlusionState.contains(.visible) }
        let windowIsOccluded = windowIsVisible.map { !$0 }

        runtimeStateLock.lock()
        cachedAppIsActive = appIsActive
        cachedWindowIsVisible = windowIsVisible
        cachedWindowIsOccluded = windowIsOccluded
        cachedViewIsPaused = view?.isPaused
        cachedViewEnableSetNeedsDisplay = view?.enableSetNeedsDisplay
        cachedPreferredFramesPerSecond = view?.preferredFramesPerSecond
        runtimeStateLock.unlock()
    }

    func shouldSuspendUISyncForBackgroundState() -> Bool {
        let state = readCachedRuntimeState()
        if state.appIsActive == false {
            return true
        }
        if state.windowIsOccluded == true {
            return true
        }
        if state.windowIsVisible == false {
            return true
        }
        return false
    }

    private func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }

    private func boolString(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    private func optionalBoolString(_ value: Bool?) -> String {
        guard let value else { return "na" }
        return boolString(value)
    }

    private func optionalIntString(_ value: Int?) -> String {
        guard let value else { return "na" }
        return "\(value)"
    }

    func startMainQueueLatencyProbe() {
        guard mainQueueProbeTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: mainQueueProbeQueue)
        timer.schedule(
            deadline: .now() + mainQueueProbeIntervalSeconds,
            repeating: mainQueueProbeIntervalSeconds,
            leeway: .milliseconds(50)
        )
        timer.setEventHandler { [weak self] in
            let scheduledAt = CACurrentMediaTime()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshCachedRuntimeStateOnMain(view: self.attachedView)
                let latencyMs = max(0.0, (CACurrentMediaTime() - scheduledAt) * 1000.0)
                self.recordMainQueueLatency(latencyMs: latencyMs)
            }
        }
        mainQueueProbeTimer = timer
        timer.resume()
    }

    func stopMainQueueLatencyProbe() {
        guard let timer = mainQueueProbeTimer else { return }
        timer.setEventHandler {}
        timer.cancel()
        mainQueueProbeTimer = nil
    }

    func setDebugMode(_ modeRaw: Int32) {
        guard let mode = DebugMode(rawValue: modeRaw) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.settings.debugMode = mode
            self.hud?.updateMode(mode.label)
        }
    }

    func toggleGrid() {
        DispatchQueue.main.async { [weak self] in
            self?.settings.showGrid.toggle()
        }
    }

    func toggleAxis() {
        DispatchQueue.main.async { [weak self] in
            self?.settings.showAxis.toggle()
        }
    }

    func toggleObjectBasis() {
        DispatchQueue.main.async { [weak self] in
            self?.settings.showObjectBasis.toggle()
        }
    }

    func togglePivot() {
        DispatchQueue.main.async { [weak self] in
            self?.settings.showPivot.toggle()
        }
    }

    func toggleTransformSpace() {
        DispatchQueue.main.async { [weak self] in
            self?.settings.toggleTransformSpace()
        }
    }

    func toggleHUD() {
        DispatchQueue.main.async { [weak self] in
            self?.settings.showHUD.toggle()
        }
    }
}
