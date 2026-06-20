import Foundation

/// A completed session persisted to disk: its stats plus the full waveform for replay.
struct SavedSession: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let mode: MeasurementMode
    let durationSeconds: Double
    let sampleRate: Double
    let metrics: BreathingMetrics
    let samples: [BreathSample]

    init(
        id: UUID = UUID(),
        date: Date,
        mode: MeasurementMode,
        durationSeconds: Double,
        sampleRate: Double,
        metrics: BreathingMetrics,
        samples: [BreathSample]
    ) {
        self.id = id
        self.date = date
        self.mode = mode
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.metrics = metrics
        self.samples = samples
    }

    /// Just the waveform values, for charting / replay.
    var waveform: [Double] { samples.map { $0.value } }
}
