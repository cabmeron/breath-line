import SwiftUI
import Combine

/// Stats for one saved session, plus an animated replay of the breathing waveform.
struct SessionDetailView: View {
    let session: SavedSession
    @StateObject private var player: WaveformReplayPlayer

    init(session: SavedSession) {
        self.session = session
        let period = (session.mode == .movement && session.metrics.targetBPM > 0)
            ? 60.0 / session.metrics.targetBPM
            : nil
        _player = StateObject(wrappedValue: WaveformReplayPlayer(
            samples: session.samples,
            sampleRate: session.sampleRate,
            guidePeriod: period
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                scoreHeader

                replaySection

                MetricsCard(metrics: session.metrics)
            }
            .padding()
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.pause() }
    }

    // MARK: - Sections

    private var scoreHeader: some View {
        VStack(spacing: 6) {
            Label(session.mode.title, systemImage: session.mode.systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("\(session.metrics.score)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
            Text(session.metrics.scoreCaption).font(.subheadline).foregroundStyle(.secondary)
            Text(session.metrics.qualitativeRating).font(.headline)
            Text(session.date, format: .dateTime.weekday().month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var replaySection: some View {
        VStack(spacing: 14) {
            BreathingWaveformView(samples: player.visible, guide: player.visibleGuide)
                .frame(height: 160)

            ProgressView(value: player.progress)
                .tint(.accentColor)

            HStack(spacing: 28) {
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 46))
                }

                Picker("Speed", selection: $player.speed) {
                    Text("1×").tag(1.0)
                    Text("2×").tag(2.0)
                    Text("4×").tag(4.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        }
    }

}

/// Steps through a recorded waveform on a timer, exposing a sliding window for display.
final class WaveformReplayPlayer: ObservableObject {
    @Published var visible: [Double] = []
    @Published var visibleGuide: [Double] = []
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var speed: Double = 2

    private let values: [Double]
    private let times: [Double]
    private let guidePeriod: Double?      // nil = no guide (non-Movement sessions)
    private let tickRate: Double          // display ticks per second
    private let stepPerTick: Double       // base samples advanced per tick at 1× speed
    private let windowSize = 300          // ~10 s at 30 Hz
    private var index = 0
    private var timer: Timer?

    init(samples: [BreathSample], sampleRate: Double, guidePeriod: Double?) {
        self.values = samples.map { $0.value }
        self.times = samples.map { $0.time }
        self.guidePeriod = guidePeriod
        self.tickRate = 30
        // At 1× we want real-time: advance `sampleRate / tickRate` samples per tick.
        self.stepPerTick = max(1, sampleRate / 30)
    }

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        guard !values.isEmpty else { return }
        if index >= values.count { index = 0 }   // restart if at the end
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / tickRate, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func pause() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let step = max(1, Int((stepPerTick * speed).rounded()))
        index = min(values.count, index + step)
        let lower = max(0, index - windowSize)
        visible = Array(values[lower..<index])
        if let period = guidePeriod {
            visibleGuide = times[lower..<index].map { BreathingGuide.value(at: $0, period: period) }
        }
        progress = Double(index) / Double(max(1, values.count))
        if index >= values.count { pause() }
    }
}
