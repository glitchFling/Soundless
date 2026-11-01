import AVFoundation
import Combine

@MainActor
final class AudioController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published var errorMessage: String?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var latest: AVAudioPCMBuffer?
    private var generation = UUID()
    private var renderTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    init() {
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: LoopRenderer.sampleRate, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func update(_ project: BeatProject) {
        guard isPlaying else { return }
        renderTask?.cancel()
        let token = generation
        renderTask = Task {
            do {
                let buffer = try await Task.detached(priority: .userInitiated) {
                    try LoopRenderer.render(project)
                }.value
                guard !Task.isCancelled, token == generation else { return }
                latest = buffer
            } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
        }
    }

    func play(_ project: BeatProject) {
        stop()
        let token = generation
        renderTask = Task {
            do {
                let buffer = try await Task.detached(priority: .userInitiated) {
                    try LoopRenderer.render(project)
                }.value
                guard !Task.isCancelled, token == generation else { return }
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
                latest = buffer
                try engine.start()
                // Queue a full loop ahead; callbacks only replenish buffers, never time notes.
                enqueue(buffer, token: token)
                enqueue(buffer, token: token)
                player.play()
                isPlaying = true
            } catch { stop(); errorMessage = error.localizedDescription }
        }
    }

    private func enqueue(_ buffer: AVAudioPCMBuffer, token: UUID) {
        player.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying, self.generation == token, let next = self.latest else { return }
                self.enqueue(next, token: token)
            }
        }
    }

    func stop() {
        generation = UUID()
        renderTask?.cancel()
        renderTask = nil
        isPlaying = false
        player.stop()
        engine.stop()
        latest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
