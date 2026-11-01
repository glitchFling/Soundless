import AVFoundation
import Combine

@MainActor
protocol LoopAudioOutput: AnyObject {
    var volume: Float { get set }
    var sampleTime: Int64? { get }
    func prepare() throws
    func replace(with loop: RenderedLoop)
    func stop()
}

@MainActor
final class EngineAudioOutput: LoopAudioOutput {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }
    var sampleTime: Int64? {
        guard let nodeTime = player.lastRenderTime,
              let time = player.playerTime(forNodeTime: nodeTime), time.isSampleTimeValid else { return nil }
        return time.sampleTime
    }

    init() {
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: LoopRenderer.sampleRate, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func prepare() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif
        if !engine.isRunning { try engine.start() }
    }

    func replace(with loop: RenderedLoop) {
        // stop resets the player clock and clears the previous loop, while the engine stays running.
        player.stop()
        player.scheduleBuffer(loop.buffer, at: nil, options: .loops, completionHandler: nil)
        player.volume = 1
        player.play()
    }

    func stop() {
        player.stop()
        engine.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

@MainActor
final class AudioController: ObservableObject {
    typealias Render = @Sendable (SoundPattern) async throws -> RenderedLoop
    @Published private(set) var isPlaying = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isUpdating = false
    @Published private(set) var playbackRevision = UUID()
    @Published var errorMessage: String?
    private let output: any LoopAudioOutput
    private let render: Render
    private var currentLoop: RenderedLoop?
    private var requestedPattern: SoundPattern?
    private var generation = UUID()
    private var renderTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    init(output: (any LoopAudioOutput)? = nil, render: @escaping Render = AudioController.renderInBackground) {
        self.output = output ?? EngineAudioOutput()
        self.render = render
        #if os(iOS)
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        #endif
    }

    deinit {
        renderTask?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    nonisolated static func renderInBackground(_ pattern: SoundPattern) async throws -> RenderedLoop {
        let worker = Task.detached(priority: .userInitiated) { try LoopRenderer.render(pattern) }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
    }

    var playbackPosition: PlaybackPosition {
        guard isPlaying, let currentLoop else { return .idle }
        return currentLoop.position(sampleTime: output.sampleTime ?? 0)
    }

    func update(_ project: BeatProject) {
        guard isPlaying || isPreparing else { return }
        let pattern = project.soundPattern
        guard requestedPattern != pattern else { return }
        request(pattern)
    }

    func play(_ project: BeatProject) {
        stop()
        errorMessage = nil
        isPreparing = true
        request(project.soundPattern)
    }

    private func request(_ pattern: SoundPattern) {
        generation = UUID()
        let token = generation
        requestedPattern = pattern
        renderTask?.cancel()
        // A newer edit can cancel an in-progress fade. Restore the old loop while rendering.
        output.volume = 1
        isUpdating = isPlaying
        let renderer = render
        renderTask = Task { [weak self] in
            do {
                let loop = try await renderer(pattern)
                try Task.checkCancellation()
                guard let self, token == self.generation else { return }
                if self.isPlaying {
                    // Fade the outgoing loop over ~8 ms. These sleeps change gain, never note timing.
                    for part in 1...4 {
                        self.output.volume = 1 - Float(part) / 4
                        try await Task.sleep(for: .milliseconds(2))
                        try Task.checkCancellation()
                        guard token == self.generation else { return }
                    }
                } else {
                    try self.output.prepare()
                }
                try Task.checkCancellation()
                guard token == self.generation else { return }
                self.output.replace(with: loop)
                self.currentLoop = loop
                self.playbackRevision = UUID()
                self.isPlaying = true
                self.isPreparing = false
                self.isUpdating = false
            } catch {
                guard let self, token == self.generation, !Task.isCancelled else { return }
                self.output.volume = 1
                self.isPreparing = false
                self.isUpdating = false
                if !self.isPlaying { self.output.stop() }
                self.requestedPattern = self.currentLoop?.pattern
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func stop() {
        generation = UUID()
        renderTask?.cancel()
        renderTask = nil
        isPlaying = false
        isPreparing = false
        isUpdating = false
        output.stop()
        output.volume = 1
        currentLoop = nil
        requestedPattern = nil
        playbackRevision = UUID()
    }
}
