import AVFoundation
import Foundation
import SwiftUI

enum CheckFailure: Error { case failed(String) }

func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw CheckFailure.failed(message) }
}

@MainActor
func eventually(_ message: String, _ condition: () async -> Bool) async throws {
    for _ in 0..<2_000 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw CheckFailure.failed("Timed out: \(message)")
}

@MainActor
final class FakeOutput: LoopAudioOutput {
    var volume: Float = 1
    var sampleTime: Int64? = 0
    var prepareCount = 0
    var loops: [RenderedLoop] = []
    func prepare() throws { prepareCount += 1 }
    func replace(with loop: RenderedLoop) { loops.append(loop); sampleTime = 0; volume = 1 }
    func stop() { sampleTime = nil }
}

// Deliberately ignores cancellation until resolved, to test late results from obsolete renders.
actor RenderGate {
    var pending: [Double: (SoundPattern, CheckedContinuation<RenderedLoop, Error>)] = [:]
    func render(_ pattern: SoundPattern) async throws -> RenderedLoop {
        try await withCheckedThrowingContinuation { pending[pattern.bpm] = (pattern, $0) }
    }
    func contains(_ bpm: Double) -> Bool { pending[bpm] != nil }
    func finish(_ bpm: Double) throws {
        guard let (pattern, continuation) = pending.removeValue(forKey: bpm) else {
            throw CheckFailure.failed("No pending render at \(bpm) BPM")
        }
        continuation.resume(with: Result { try LoopRenderer.render(pattern) })
    }
    func fail(_ bpm: Double) throws {
        guard let (_, continuation) = pending.removeValue(forKey: bpm) else {
            throw CheckFailure.failed("No pending render at \(bpm) BPM")
        }
        continuation.resume(throwing: CheckFailure.failed("Injected render failure"))
    }
}

@main
struct PlaybackChecks {
    @MainActor
    static func main() async throws {
        try timingAndRendering()
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try LoopRenderer.render(BeatProject().soundPattern)
        }
        do {
            _ = try await cancelled.value
            throw CheckFailure.failed("Cancelled rendering did not stop")
        } catch is CancellationError { }
        print("PASS: all step boundaries, rests, looping, waveforms, and render cancellation")
        try geometry()
        print("PASS: waveform dots share the exact trace geometry")
        try await immediateReplay()
        print("PASS: immediate replay, latest edit wins, names do not restart, engine stays active")
        try await startupAndStop()
        print("PASS: startup edits supersede old renders; stopped edits stay silent")
        try await fadeAndFailure()
        print("PASS: cancelled fades cannot restart; render failures preserve old playback")
    }

    static func timingAndRendering() throws {
        for bpm in [40.0, 60, 120, 137, 240] {
            for waveform in Waveform.allCases {
                let pattern = BeatProject(bpm: bpm, waveform: waveform).soundPattern
                let loop = try LoopRenderer.render(pattern)
                try check(Int(loop.buffer.frameLength) == loop.timing.frameCount, "PCM length and timeline differ")
                try check(loop.timing.frameCount == Int((44_100 * 240 / bpm).rounded()), "Wrong loop duration")
                for step in 0..<16 {
                    let start = loop.timing.boundaries[step]
                    let end = loop.timing.boundaries[step + 1]
                    for frame in [start, end - 1] {
                        let position = loop.position(sampleTime: Int64(frame))
                        try check(position.step == step, "Wrong step at boundary")
                        try check(position.note == pattern.steps[step], "Wrong rendered note/rest")
                        try check(position.waveform == waveform, "Wrong rendered waveform")
                    }
                    let output = loop.buffer.floatChannelData![0]
                    try check(output[start] == 0 && output[end - 1] == 0, "Note envelope has nonzero endpoints")
                    if pattern.steps[step] == nil {
                        try check((start..<end).allSatisfy { output[$0] == 0 }, "Rest contains sound")
                    }
                }
                for cycles in [1, 100, 10_000] {
                    let position = loop.position(sampleTime: Int64(loop.timing.frameCount * cycles))
                    try check(position.step == 0 && position.progress == 0, "Loop failed to wrap")
                }
                try check(loop.position(sampleTime: -1).step == 0, "Negative startup time should clamp")
            }
        }
        try check(PlaybackPosition.idle.step == nil && !PlaybackPosition.idle.isSounding, "Idle state is not silent")
    }

    static func geometry() throws {
        let bounds = CGRect(x: 5, y: 5, width: 90, height: 26)
        for waveform in Waveform.allCases {
            for index in 0...120 {
                let point = WaveformGeometry.point(waveform: waveform, progress: Double(index) / 120, in: bounds)
                try check(bounds.contains(point) || point.x == bounds.maxX, "Dot is outside its trace bounds")
                try check(point.x.isFinite && point.y.isFinite, "Invalid dot geometry")
            }
        }
    }

    @MainActor
    static func immediateReplay() async throws {
        let gate = RenderGate(), output = FakeOutput()
        let controller = AudioController(output: output, render: { try await gate.render($0) })
        var project = BeatProject()
        controller.play(project)
        try await eventually("initial render") { await gate.contains(120) }
        try await gate.finish(120)
        try await eventually("initial playback") { controller.isPlaying }
        output.sampleTime = 44_100
        try check(controller.playbackPosition.step == 8, "Player sample clock did not drive progress")
        let revision = controller.playbackRevision
        project.name = "Renamed"
        controller.update(project)
        try check(controller.playbackRevision == revision && !controller.isUpdating, "Name change restarted audio")
        project.bpm = 121
        controller.update(project)
        try await eventually("older edit") { await gate.contains(121) }
        project.bpm = 122
        project.steps[0] = 72
        project.waveform = .triangle
        controller.update(project)
        try await eventually("newest edit") { await gate.contains(122) }
        try await gate.finish(122)
        try await eventually("replay") { output.loops.count == 2 }
        try check(controller.playbackPosition.step == 0 && controller.playbackPosition.note == 72, "Replay did not start latest pattern at step 1")
        try check(controller.playbackPosition.waveform == .triangle, "Display uses editable rather than playing waveform")
        try await gate.finish(121)
        try await Task.sleep(for: .milliseconds(20))
        try check(output.loops.count == 2 && output.loops.last?.pattern.bpm == 122, "Late render replaced the latest edit")
        try check(output.prepareCount == 1, "Edit restarted the audio engine")
        controller.stop()
        try check(controller.playbackPosition == .idle, "Stop did not reset visual state")
        project.bpm = 123
        controller.update(project)
        try await Task.sleep(for: .milliseconds(20))
        let stoppedRender = await gate.contains(123)
        try check(!stoppedRender && !controller.isPreparing && !controller.isPlaying, "Editing while stopped started audio")
    }

    @MainActor
    static func startupAndStop() async throws {
        let gate = RenderGate(), output = FakeOutput()
        let controller = AudioController(output: output, render: { try await gate.render($0) })
        var project = BeatProject()
        controller.play(project)
        try await eventually("startup") { await gate.contains(120) }
        project.bpm = 140
        controller.update(project)
        try await eventually("new startup") { await gate.contains(140) }
        try await gate.finish(120)
        try await Task.sleep(for: .milliseconds(20))
        try check(output.loops.isEmpty, "Obsolete startup played")
        try await gate.finish(140)
        try await eventually("updated startup playback") { controller.isPlaying }
        try check(output.loops.last?.pattern.bpm == 140, "Startup edit was lost")
        project.bpm = 150
        controller.update(project)
        try await eventually("pending edit") { await gate.contains(150) }
        controller.stop()
        try await gate.finish(150)
        try await Task.sleep(for: .milliseconds(20))
        try check(!controller.isPlaying && output.loops.count == 1, "Stop was undone by late render")
        project.bpm = 160
        controller.play(project)
        try await eventually("pending initial render") { await gate.contains(160) }
        controller.stop()
        try await gate.finish(160)
        try await Task.sleep(for: .milliseconds(20))
        try check(!controller.isPlaying && !controller.isPreparing && output.loops.count == 1, "Cancel loading restarted audio")
    }

    @MainActor
    static func fadeAndFailure() async throws {
        let gate = RenderGate(), output = FakeOutput()
        let controller = AudioController(output: output, render: { try await gate.render($0) })
        var project = BeatProject()
        controller.play(project)
        try await eventually("initial render") { await gate.contains(120) }
        try await gate.finish(120)
        try await eventually("initial play") { controller.isPlaying }
        project.bpm = 130
        controller.update(project)
        try await eventually("fade render") { await gate.contains(130) }
        try await gate.finish(130)
        try await eventually("fade started") { output.volume < 1 }
        controller.stop()
        try await Task.sleep(for: .milliseconds(30))
        try check(output.loops.count == 1 && !controller.isPlaying && output.volume == 1, "Cancelled fade replaced the loop")
        project.bpm = 140
        controller.play(project)
        try await eventually("restart") { await gate.contains(140) }
        try await gate.finish(140)
        try await eventually("restart playback") { controller.isPlaying }
        project.bpm = 150
        controller.update(project)
        try await eventually("failed render") { await gate.contains(150) }
        try await gate.fail(150)
        try await eventually("error reported") { controller.errorMessage != nil }
        try check(controller.isPlaying && !controller.isUpdating && output.loops.last?.pattern.bpm == 140, "Render failure stopped or replaced the old loop")
        controller.stop()
    }
}
