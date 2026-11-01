import AVFoundation

// The buffer is written only during rendering and is immutable once handed to the player.
struct RenderedLoop: @unchecked Sendable {
    let pattern: SoundPattern
    let timing: LoopTiming
    let buffer: AVAudioPCMBuffer

    func position(sampleTime: Int64) -> PlaybackPosition { timing.position(sampleTime: sampleTime, pattern: pattern) }
}

enum LoopRenderer {
    static let sampleRate = 44_100.0

    static func render(_ pattern: SoundPattern) throws -> RenderedLoop {
        let project = try BeatProject(bpm: pattern.bpm, waveform: pattern.waveform, steps: pattern.steps).validated()
        let timing = LoopTiming(bpm: project.bpm, sampleRate: sampleRate)
        let count = timing.frameCount
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let output = buffer.floatChannelData?[0] else { throw CocoaError(.coderInvalidValue) }
        buffer.frameLength = AVAudioFrameCount(count)
        for step in 0..<16 {
            try Task.checkCancellation()
            let start = timing.boundaries[step]
            let end = timing.boundaries[step + 1]
            let length = end - start
            let frequency = project.steps[step].map { 440 * pow(2, Double($0 - 69) / 12) }
            for offset in 0..<length {
                if offset % 1024 == 0 { try Task.checkCancellation() }
                guard let frequency else { output[start + offset] = 0; continue }
                let phase = (Double(offset) * frequency / sampleRate).truncatingRemainder(dividingBy: 1)
                var value = 0.0
                switch project.waveform {
                case .sine: value = sin(2 * .pi * phase)
                case .square, .triangle, .sawtooth:
                    // Additive synthesis excludes harmonics above Nyquist to limit aliasing.
                    let harmonics = min(64, Int((sampleRate / 2 - 1) / frequency))
                    for harmonic in 1...max(1, harmonics) {
                        let h = Double(harmonic)
                        switch project.waveform {
                        case .square:
                            if harmonic % 2 == 1 { value += 4 / .pi * sin(2 * .pi * h * phase) / h }
                        case .triangle:
                            if harmonic % 2 == 1 {
                                let sign = harmonic % 4 == 1 ? 1.0 : -1.0
                                value += 8 / (.pi * .pi) * sign * sin(2 * .pi * h * phase) / (h * h)
                            }
                        case .sawtooth: value -= 2 / .pi * sin(2 * .pi * h * phase) / h
                        case .sine: break
                        }
                    }
                }
                let attack = min(1, Double(offset) / (sampleRate * 0.005))
                let release = min(1, Double(length - 1 - offset) / (sampleRate * 0.012))
                output[start + offset] = Float(value * attack * release * 0.22)
            }
        }
        return RenderedLoop(pattern: pattern, timing: timing, buffer: buffer)
    }
}
