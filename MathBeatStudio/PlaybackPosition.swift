import Foundation

struct PlaybackPosition: Equatable {
    let step: Int?
    let note: Int?
    let progress: Double
    let waveform: Waveform?

    static let idle = PlaybackPosition(step: nil, note: nil, progress: 0, waveform: nil)
    var isSounding: Bool { step != nil && note != nil }
}

struct LoopTiming: Sendable {
    // Includes the exclusive end of step 16. Rendering and visuals share these boundaries.
    let boundaries: [Int]
    var frameCount: Int { boundaries[16] }

    init(bpm: Double, sampleRate: Double) {
        let framesPerStep = sampleRate * 60 / bpm / 4
        boundaries = (0...16).map { Int((Double($0) * framesPerStep).rounded()) }
    }

    func position(sampleTime: Int64, pattern: SoundPattern) -> PlaybackPosition {
        let frame = Int(max(0, sampleTime) % Int64(frameCount))
        let step = (0..<16).first { frame < boundaries[$0 + 1] } ?? 15
        return PlaybackPosition(step: step, note: pattern.steps[step],
                                progress: Double(frame) / Double(frameCount), waveform: pattern.waveform)
    }
}
