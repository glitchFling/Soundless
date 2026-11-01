import SwiftUI

func studioNoteName(_ midi: Int) -> String {
    let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    return "\(names[midi % 12])\(midi / 12 - 1)"
}

struct StudioPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func studioCard() -> some View {
        self.padding(20)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.07)))
    }
}

enum WaveformGeometry {
    static func point(waveform: Waveform, progress: Double, in rect: CGRect) -> CGPoint {
        let x = min(1, max(0, progress))
        let phase = (x * 2).truncatingRemainder(dividingBy: 1)
        let value: Double
        switch waveform {
        case .sine: value = sin(2 * .pi * phase)
        case .square: value = phase < 0.5 ? 1 : -1
        case .triangle: value = 1 - 4 * abs(phase - 0.5)
        case .sawtooth: value = 2 * phase - 1
        }
        return CGPoint(x: rect.minX + rect.width * x, y: rect.midY - value * rect.height * 0.42)
    }
}

struct WaveformTrace: Shape {
    let waveform: Waveform
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for sample in 0...120 {
            let point = WaveformGeometry.point(waveform: waveform, progress: Double(sample) / 120, in: rect)
            if sample == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

struct WaveformPreview: View {
    let waveform: Waveform
    let selected: Bool
    let position: PlaybackPosition
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size).insetBy(dx: 5, dy: 5)
            let progress = reduceMotion ? 0.125 : position.progress
            ZStack(alignment: .topLeading) {
                WaveformTrace(waveform: waveform)
                    .path(in: bounds)
                    .stroke(selected ? tint : .gray, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                if selected {
                    Circle().fill(tint)
                        .frame(width: 8, height: 8)
                        .shadow(color: tint.opacity(position.isSounding ? 0.65 : 0), radius: 6)
                        .opacity(position.isSounding ? 1 : 0.3)
                        .position(WaveformGeometry.point(waveform: waveform, progress: progress, in: bounds))
                }
            }
        }
        .frame(height: 36)
        .accessibilityHidden(true)
    }
}
