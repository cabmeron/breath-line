import Foundation
import CoreMotion
import UIKit

/// Drives a timed breathing-capture session off Core Motion's fused `deviceMotion` stream.
///
/// Motion updates arrive on a background `OperationQueue` (serial), where samples are
/// accumulated and the live breath counter runs. UI-facing `@Published` properties are
/// updated back on the main queue.
final class BreathingSession: ObservableObject {

    enum State: Equatable { case idle, recording, finished }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var liveWaveform: [Double] = []
    @Published private(set) var liveBreathCount: Int = 0
    @Published private(set) var metrics: BreathingMetrics = .empty
    /// Normalized [-1, 1] guide path aligned to `liveWaveform` (Movement mode only; empty otherwise).
    @Published private(set) var liveGuide: [Double] = []
    /// Full recorded waveform of the just-finished session (used for saving / replay).
    @Published private(set) var recordedSamples: [BreathSample] = []
    /// Measurement mode chosen for the just-finished session.
    private(set) var lastMode: MeasurementMode = .movement
    /// Target pace (breaths/min) for the just-finished Movement session.
    private(set) var lastTargetBPM: Double = 6

    let sampleRate: Double = 30.0

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1   // serialize the motion handler
        q.name = "BreathingSession.motion"
        return q
    }()
    private let processor = SignalProcessor()
    private let haptics = HapticFeedback()

    private var samples: [BreathSample] = []
    private var duration: TimeInterval = 60
    private var startTimestamp: TimeInterval = 0
    private var finished = false
    private var vibrate = false

    /// Movement below this fraction of recent amplitude away from the path doesn't buzz.
    private let vibrationDeadzone = 0.15
    /// Amplitude floor (radians) so near-stillness doesn't get normalized into wild swings.
    private let vibrationAmplitudeFloor = 0.05

    // Live baseline removal (slow exponential moving average → high-pass).
    private var baseline = 0.0
    private var baselineReady = false
    private let baselineAlpha = 0.02

    // Live breath detection (upward zero-crossing with a refractory period).
    private var wasPositive = false
    private var lastBreathTime: TimeInterval = -10
    private var liveBreaths = 0

    private let displayWindow = 300   // ~10 s of samples shown live

    var isMotionAvailable: Bool { motion.isDeviceMotionAvailable }

    // MARK: - Control

    func start(duration: TimeInterval, mode: MeasurementMode, targetBPM: Double = 6, vibrate: Bool = false) {
        guard motion.isDeviceMotionAvailable else { return }

        // Reset state.
        self.duration = duration
        self.lastMode = mode
        self.lastTargetBPM = targetBPM
        self.vibrate = vibrate && mode == .movement && targetBPM > 0
        samples.removeAll(keepingCapacity: true)
        recordedSamples = []
        liveWaveform = []
        liveGuide = []
        liveBreathCount = 0
        metrics = .empty
        elapsed = 0
        remaining = duration
        finished = false
        baseline = 0
        baselineReady = false
        wasPositive = false
        lastBreathTime = -10
        liveBreaths = 0
        state = .recording

        UIApplication.shared.isIdleTimerDisabled = true
        if self.vibrate { haptics.start() }

        motion.deviceMotionUpdateInterval = 1.0 / sampleRate
        motion.startDeviceMotionUpdates(to: queue) { [weak self] deviceMotion, _ in
            guard let self, let deviceMotion else { return }
            self.handle(deviceMotion)
        }
    }

    func cancel() {
        motion.stopDeviceMotionUpdates()
        haptics.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        DispatchQueue.main.async {
            self.state = .idle
            self.elapsed = 0
            self.remaining = self.duration
        }
    }

    func reset() {
        state = .idle
        metrics = .empty
        liveWaveform = []
        liveBreathCount = 0
        elapsed = 0
        remaining = duration
    }

    // MARK: - Capture (background queue)

    private func handle(_ dm: CMDeviceMotion) {
        guard !finished else { return }

        let timestamp = dm.timestamp
        if samples.isEmpty { startTimestamp = timestamp }
        let t = timestamp - startTimestamp

        // `attitude.pitch` is the forward/back tilt — the dominant breathing axis when the
        // phone lies flat on the chest or belly.
        let raw = dm.attitude.pitch
        if !baselineReady { baseline = raw; baselineReady = true }
        baseline += baselineAlpha * (raw - baseline)
        let value = raw - baseline

        samples.append(BreathSample(time: t, value: value))

        // Live breath count: rising edge through zero, with a 1.2 s refractory window.
        let positive = value > 0
        if positive, !wasPositive, t - lastBreathTime > 1.2 {
            lastBreathTime = t
            liveBreaths += 1
        }
        wasPositive = positive

        let recent = Array(samples.suffix(displayWindow))
        let displaySlice = smoothedForDisplay(recent.map { $0.value })
        let guideSlice = guidePath(for: recent)
        let breathsNow = liveBreaths
        let elapsedNow = t

        // Vibration feedback: buzz harder the farther the user is from the guide path.
        if vibrate {
            let period = 60.0 / lastTargetBPM
            let target = BreathingGuide.value(at: t, period: period)
            let amplitude = max(recent.map { abs($0.value) }.max() ?? vibrationAmplitudeFloor, vibrationAmplitudeFloor)
            let userPosition = max(-1, min(1, value / amplitude))
            let deviation = abs(userPosition - target) / 2   // 0...1
            let intensity = max(0, (deviation - vibrationDeadzone) / (1 - vibrationDeadzone))
            haptics.setIntensity(intensity)
        }

        if elapsedNow >= duration {
            finished = true
            motion.stopDeviceMotionUpdates()
            haptics.stop()
            let result = processor.analyze(samples: samples, sampleRate: sampleRate, mode: lastMode, targetBPM: lastTargetBPM)
            let allSamples = samples
            DispatchQueue.main.async {
                self.elapsed = self.duration
                self.remaining = 0
                self.liveWaveform = displaySlice
                self.liveGuide = guideSlice
                self.liveBreathCount = breathsNow
                self.metrics = result
                self.recordedSamples = allSamples
                self.state = .finished
                UIApplication.shared.isIdleTimerDisabled = false
            }
            return
        }

        DispatchQueue.main.async {
            self.elapsed = elapsedNow
            self.remaining = max(0, self.duration - elapsedNow)
            self.liveWaveform = displaySlice
            self.liveGuide = guideSlice
            self.liveBreathCount = breathsNow
        }
    }

    /// Normalized guide path for the given window — only in Movement mode, empty otherwise.
    private func guidePath(for window: [BreathSample]) -> [Double] {
        guard lastMode == .movement, lastTargetBPM > 0 else { return [] }
        let period = 60.0 / lastTargetBPM
        return window.map { BreathingGuide.value(at: $0.time, period: period) }
    }

    /// Trailing moving average to take visual jitter off the live waveform (display only —
    /// raw samples are kept intact for analysis, which does its own filtering).
    private func smoothedForDisplay(_ x: [Double]) -> [Double] {
        let window = 5
        guard x.count >= window else { return x }
        var out = [Double](repeating: 0, count: x.count)
        var sum = 0.0
        for i in 0..<x.count {
            sum += x[i]
            if i >= window { sum -= x[i - window] }
            out[i] = sum / Double(min(i + 1, window))
        }
        return out
    }
}
