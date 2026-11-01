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

struct WaveformTrace: Shape {
    let waveform: Waveform
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for sample in 0...120 {
            let x = Double(sample) / 120
            let phase = (x * 2).truncatingRemainder(dividingBy: 1)
            let value: Double
            switch waveform {
            case .sine: value = sin(2 * .pi * phase)
            case .square: value = phase < 0.5 ? 1 : -1
            case .triangle: value = 1 - 4 * abs(phase - 0.5)
            case .sawtooth: value = 2 * phase - 1
            }
            let point = CGPoint(x: rect.minX + rect.width * x, y: rect.midY - value * rect.height * 0.42)
            if sample == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
