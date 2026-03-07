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
    var frameSampleCount: Int
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

        guard hudAccumulatedTime >= hudUpdateInterval else {
            return
        }

        let suppressHUDUpdates = shouldSuspendUISyncForBackgroundState()
        let hudLevel = settings.hudLevel
        hudAccumulatedTime.formTruncatingRemainder(dividingBy: hudUpdateInterval)

        guard suppressHUDUpdates == false, hudLevel != .off else {
            hudOverlayPass?.update(lines: [])
            return
        }

        let diagnostics = consumeHUDDiagnostics()
        let frameMs: Double
        let fps: Double
        let cpuMs: Double
        if diagnostics.frameSampleCount > 0 {
            frameMs = diagnostics.avgUpdateMs + diagnostics.avgRenderMs + diagnostics.avgFrameGapMs
            fps = frameMs > 0.0001 ? 1000.0 / frameMs : 0.0
            cpuMs = diagnostics.avgUpdateMs + diagnostics.avgRenderMs
        } else {
            frameMs = 0.0
            fps = 0.0
            cpuMs = 0.0
        }
        let overlayLines = makeHUDOverlayLines(
            fps: fps,
            frameMs: frameMs,
            cpuMs: cpuMs,
            gpuMs: diagnostics.avgCommandBufferLatencyMs,
            diagnostics: diagnostics,
            hudLevel: hudLevel
        )
        hudOverlayPass?.update(lines: overlayLines)
    }

    private func makeHUDOverlayLines(
        fps: Double,
        frameMs: Double,
        cpuMs: Double,
        gpuMs: Double,
        diagnostics: HUDDiagnosticsSnapshot,
        hudLevel: HUDLevel
    ) -> [String] {
        var lines: [String] = []
        lines.reserveCapacity(10)
        lines.append("RenderLab")
        lines.append(String(format: "FPS: %.0f", fps))
        lines.append(String(format: "CPU: %.2f ms", cpuMs))
        lines.append(String(format: "GPU: %.2f ms", gpuMs))

        guard hudLevel == .verbose else {
            return lines
        }

        lines.append(String(format: "Frame: %.2f ms", frameMs))
        lines.append("Mode: \(settings.debugMode.label)")
        lines.append(contentsOf: makeHUDDiagnosticsLines(snapshot: diagnostics))
        return lines
    }

    /// Records timing diagnostics for a single rendered frame.
    ///
    /// This method accumulates update, render, and frame-gap timings into
    /// both lifetime and dump-window diagnostic counters. It also tracks
    /// slow-frame thresholds, maximum observed frame gap, and per-pass
    /// render durations keyed by pass name.
    ///
    /// - Parameters:
    ///   - updateMs: Time spent updating frame state, in milliseconds.
    ///   - renderMs: Time spent rendering the frame, in milliseconds.
    ///   - frameGapMs: Time elapsed since the previous frame, in milliseconds.
    ///   - passDurationsMs: Per-pass render durations, keyed by pass name.
    func recordFrameDiagnostics(
        updateMs: Double,
        renderMs: Double,
        frameGapMs: Double,
        passDurationsMs: [String: Double]
    ) {
        diagnosticsLock.lock()
        let now = CACurrentMediaTime()
        hudRollingFrameSamples.append(
            (
                timestamp: now,
                updateMs: updateMs,
                renderMs: renderMs,
                frameGapMs: frameGapMs,
                passDurationsMs: passDurationsMs
            )
        )
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
            diagnosticsDumpPassMsAccum[name, default: 0.0] += ms
            if diagnosticsDumpPassOrder.contains(name) == false {
                diagnosticsDumpPassOrder.append(name)
            }
        }
        trimHUDRollingLocked(now: now)
        diagnosticsLock.unlock()
    }

    func recordMainQueueLatency(latencyMs: Double) {
        diagnosticsLock.lock()
        let now = CACurrentMediaTime()
        hudRollingMainQueueLatencySamples.append((timestamp: now, latencyMs: latencyMs))

        diagnosticsDumpMainQueueLatencyMsAccum += latencyMs
        diagnosticsDumpMainQueueLatencySamples += 1
        diagnosticsDumpMainQueueLatencyMaxMs = max(diagnosticsDumpMainQueueLatencyMaxMs, latencyMs)
        if latencyMs >= 16.0 {
            diagnosticsDumpMainQueueLatencyOver16Count += 1
        }
        if latencyMs >= 33.0 {
            diagnosticsDumpMainQueueLatencyOver33Count += 1
        }
        trimHUDRollingLocked(now: now)
        diagnosticsLock.unlock()
    }

    func recordCommandBufferCommitted() {
        diagnosticsLock.lock()
        let now = CACurrentMediaTime()
        diagnosticsInFlightCommandBuffers += 1
        hudRollingInFlightSamples.append((timestamp: now, inFlight: diagnosticsInFlightCommandBuffers))
        diagnosticsDumpPeakInFlightCommandBuffers = max(
            diagnosticsDumpPeakInFlightCommandBuffers,
            diagnosticsInFlightCommandBuffers
        )
        trimHUDRollingLocked(now: now)
        diagnosticsLock.unlock()
    }

    func recordCommandBufferCompleted(committedAt commitTime: Double) {
        let latencyMs = max(0.0, (CACurrentMediaTime() - commitTime) * 1000.0)
        diagnosticsLock.lock()
        let now = CACurrentMediaTime()
        hudRollingCommandBufferLatencySamples.append((timestamp: now, latencyMs: latencyMs))
        diagnosticsDumpCommandBufferLatencyMsAccum += latencyMs
        diagnosticsDumpCommandBufferLatencySamples += 1
        diagnosticsInFlightCommandBuffers = max(0, diagnosticsInFlightCommandBuffers - 1)
        hudRollingInFlightSamples.append((timestamp: now, inFlight: diagnosticsInFlightCommandBuffers))
        trimHUDRollingLocked(now: now)
        diagnosticsLock.unlock()
    }

    func recordSceneSnapshotPublish() {
        diagnosticsLock.lock()
        let now = CACurrentMediaTime()
        hudRollingSceneSnapshotPublishTimes.append(now)
        diagnosticsDumpSceneSnapshotPublishes += 1
        trimHUDRollingLocked(now: now)
        diagnosticsLock.unlock()
    }

    func recordSelectedTransformPublish() {
        diagnosticsLock.lock()
        let now = CACurrentMediaTime()
        hudRollingSelectedTransformPublishTimes.append(now)
        diagnosticsDumpSelectedTransformPublishes += 1
        trimHUDRollingLocked(now: now)
        diagnosticsLock.unlock()
    }

    func recordInterpolationSnapshotPublish() {
        diagnosticsLock.lock()
        let now = CACurrentMediaTime()
        hudRollingInterpolationPublishTimes.append(now)
        diagnosticsDumpInterpolationPublishes += 1
        trimHUDRollingLocked(now: now)
        diagnosticsLock.unlock()
    }

    private func trimHUDRollingLocked(now: Double) {
        let cutoff = now - hudRollingWindowSeconds

        while let first = hudRollingFrameSamples.first, first.timestamp < cutoff {
            hudRollingFrameSamples.removeFirst()
        }
        while let first = hudRollingCommandBufferLatencySamples.first, first.timestamp < cutoff {
            hudRollingCommandBufferLatencySamples.removeFirst()
        }
        while let first = hudRollingMainQueueLatencySamples.first, first.timestamp < cutoff {
            hudRollingMainQueueLatencySamples.removeFirst()
        }
        while let first = hudRollingSceneSnapshotPublishTimes.first, first < cutoff {
            hudRollingSceneSnapshotPublishTimes.removeFirst()
        }
        while let first = hudRollingSelectedTransformPublishTimes.first, first < cutoff {
            hudRollingSelectedTransformPublishTimes.removeFirst()
        }
        while let first = hudRollingInterpolationPublishTimes.first, first < cutoff {
            hudRollingInterpolationPublishTimes.removeFirst()
        }
        while let first = hudRollingInFlightSamples.first, first.timestamp < cutoff {
            hudRollingInFlightSamples.removeFirst()
        }
    }

    private func updateDiagnosticsDump(dt: Double) {
        guard settings.enableDiagnosticsLogDump else {
            resetDiagnosticsDumpWindow()
            return
        }
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

            resetDiagnosticsDumpWindowLocked(inFlightCommandBuffers: inFlight)
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

    private func resetDiagnosticsDumpWindow() {
        diagnosticsLock.lock()
        let inFlight = diagnosticsInFlightCommandBuffers
        resetDiagnosticsDumpWindowLocked(inFlightCommandBuffers: inFlight)
        diagnosticsLock.unlock()
    }

    private func resetDiagnosticsDumpWindowLocked(inFlightCommandBuffers: Int) {
        diagnosticsDumpAccumulatedTime = 0.0
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
        diagnosticsDumpPeakInFlightCommandBuffers = inFlightCommandBuffers
        diagnosticsDumpSceneSnapshotPublishes = 0
        diagnosticsDumpSelectedTransformPublishes = 0
        diagnosticsDumpInterpolationPublishes = 0
    }

    private func consumeHUDDiagnostics() -> HUDDiagnosticsSnapshot {
        diagnosticsLock.lock()
        let now = CACurrentMediaTime()
        trimHUDRollingLocked(now: now)

        let frameCount = hudRollingFrameSamples.count
        let avgUpdateMs: Double
        let avgRenderMs: Double
        let avgFrameGapMs: Double
        let maxFrameGapMs: Double
        let frameGapOver33PerSecond: Double
        let frameGapOver100PerSecond: Double
        let avgPassMs: [(name: String, ms: Double)]
        let window = max(hudRollingWindowSeconds, 0.0001)

        if frameCount > 0 {
            var updateSum = 0.0
            var renderSum = 0.0
            var frameGapSum = 0.0
            var frameGapMax = 0.0
            var frameGapOver33Count = 0
            var frameGapOver100Count = 0
            var passOrder: [String] = []
            var passMap: [String: Double] = [:]

            for frameSample in hudRollingFrameSamples {
                updateSum += frameSample.updateMs
                renderSum += frameSample.renderMs
                frameGapSum += frameSample.frameGapMs
                frameGapMax = max(frameGapMax, frameSample.frameGapMs)
                if frameSample.frameGapMs >= 33.0 {
                    frameGapOver33Count += 1
                }
                if frameSample.frameGapMs >= 100.0 {
                    frameGapOver100Count += 1
                }
                for (name, ms) in frameSample.passDurationsMs {
                    passMap[name, default: 0.0] += ms
                    if passOrder.contains(name) == false {
                        passOrder.append(name)
                    }
                }
            }

            avgUpdateMs = updateSum / Double(frameCount)
            avgRenderMs = renderSum / Double(frameCount)
            avgFrameGapMs = frameGapSum / Double(frameCount)
            maxFrameGapMs = frameGapMax
            frameGapOver33PerSecond = Double(frameGapOver33Count) / window
            frameGapOver100PerSecond = Double(frameGapOver100Count) / window
            avgPassMs = passOrder.compactMap { name -> (name: String, ms: Double)? in
                guard let sumMs = passMap[name] else { return nil }
                return (name: name, ms: sumMs / Double(frameCount))
            }
        } else {
            avgUpdateMs = 0.0
            avgRenderMs = 0.0
            avgFrameGapMs = 0.0
            maxFrameGapMs = 0.0
            frameGapOver33PerSecond = 0.0
            frameGapOver100PerSecond = 0.0
            avgPassMs = []
        }

        let avgCommandBufferLatencyMs: Double
        if hudRollingCommandBufferLatencySamples.isEmpty {
            avgCommandBufferLatencyMs = 0.0
        } else {
            let latencySum = hudRollingCommandBufferLatencySamples.reduce(0.0) { partialResult, sample in
                partialResult + sample.latencyMs
            }
            avgCommandBufferLatencyMs = latencySum / Double(hudRollingCommandBufferLatencySamples.count)
        }

        let avgMainQueueLatencyMs: Double
        let maxMainQueueLatencyMs: Double
        let mainQueueLatencyOver16PerSecond: Double
        let mainQueueLatencyOver33PerSecond: Double
        if hudRollingMainQueueLatencySamples.isEmpty {
            avgMainQueueLatencyMs = 0.0
            maxMainQueueLatencyMs = 0.0
            mainQueueLatencyOver16PerSecond = 0.0
            mainQueueLatencyOver33PerSecond = 0.0
        } else {
            var latencySum = 0.0
            var latencyMax = 0.0
            var over16Count = 0
            var over33Count = 0
            for sample in hudRollingMainQueueLatencySamples {
                latencySum += sample.latencyMs
                latencyMax = max(latencyMax, sample.latencyMs)
                if sample.latencyMs >= 16.0 {
                    over16Count += 1
                }
                if sample.latencyMs >= 33.0 {
                    over33Count += 1
                }
            }
            avgMainQueueLatencyMs = latencySum / Double(hudRollingMainQueueLatencySamples.count)
            maxMainQueueLatencyMs = latencyMax
            mainQueueLatencyOver16PerSecond = Double(over16Count) / window
            mainQueueLatencyOver33PerSecond = Double(over33Count) / window
        }

        let scenePerSecond = Double(hudRollingSceneSnapshotPublishTimes.count) / window
        let selectedPerSecond = Double(hudRollingSelectedTransformPublishTimes.count) / window
        let interpolationPerSecond = Double(hudRollingInterpolationPublishTimes.count) / window
        let inFlight = diagnosticsInFlightCommandBuffers
        let rollingPeakInFlight = hudRollingInFlightSamples.reduce(inFlight) { partialResult, sample in
            max(partialResult, sample.inFlight)
        }
        diagnosticsLock.unlock()

        return HUDDiagnosticsSnapshot(
            frameSampleCount: frameCount,
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
            peakInFlightCommandBuffers: rollingPeakInFlight,
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

    /// Starts a repeating probe that measures main-queue dispatch latency.
    ///
    /// This method creates a background `DispatchSourceTimer` if one is not already
    /// running. On each timer tick, it enqueues a small block onto the main queue,
    /// refreshes cached runtime state associated with the attached view, and records
    /// the elapsed time between scheduling and execution as main-thread latency in
    /// milliseconds.
    ///
    /// The probe is intended as a lightweight responsiveness signal for detecting
    /// main-thread congestion or UI scheduling delays.
    ///
    /// - Important: This method is a no-op if the probe timer has already been started.
    /// - Note: The timer runs on `mainQueueProbeQueue`, while the measured work is
    ///   dispatched asynchronously onto `DispatchQueue.main`.
    /// - Note: Captures `self` weakly in both timer and main-queue handlers to avoid
    ///   retain cycles.
    /// - SeeAlso: `recordMainQueueLatency(latencyMs:)`
    /// - SeeAlso: `refreshCachedRuntimeStateOnMain(view:)`
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
            self?.settings.toggleHUD()
        }
    }

    func toggleDiagnosticsLogDump() {
        DispatchQueue.main.async { [weak self] in
            self?.settings.enableDiagnosticsLogDump.toggle()
        }
    }
}
