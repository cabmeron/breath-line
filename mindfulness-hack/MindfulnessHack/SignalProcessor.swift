import Foundation

/// Turns a raw tilt waveform into breathing metrics.
///
/// The capture pipeline is the same for both modes:
///   1. High-pass  (subtract a long moving average) → removes posture drift.
///   2. Low-pass   (short moving average)           → removes jitter.
///   3. Peak detection with a minimum spacing       → one peak per breath.
///
/// The *score* then depends on the chosen `MeasurementMode`:
///   - `.movement`  → how well the user followed the paced guide path at `targetBPM`.
///   - `.stillness` → how little the spot moved (low breathing-band RMS).
///
/// For production you'd swap steps 1–2 for a proper Butterworth band-pass via `Accelerate`.
struct SignalProcessor {

    func analyze(
        samples: [BreathSample],
        sampleRate: Double,
        mode: MeasurementMode,
        targetBPM: Double = 0
    ) -> BreathingMetrics {
        let duration = samples.last?.time ?? 0

        func metrics(
            bpm: Double = 0,
            count: Int = 0,
            intervalCV: Double = 0,
            amplitudeCV: Double = 0,
            movementRMS: Double = 0,
            score: Int = 0
        ) -> BreathingMetrics {
            BreathingMetrics(
                mode: mode,
                breathsPerMinute: bpm,
                breathCount: count,
                intervalCV: intervalCV,
                amplitudeCV: amplitudeCV,
                movementRMS: movementRMS,
                targetBPM: targetBPM,
                score: score,
                durationSeconds: duration
            )
        }

        // Need at least a few seconds of data to say anything.
        guard samples.count > Int(sampleRate * 5) else { return metrics() }

        let raw = samples.map { $0.value }

        // Band-pass ~0.1–0.5 Hz.
        let highPassWindow = Int(sampleRate * 6.0)         // removes drift slower than ~0.16 Hz
        let lowPassWindow  = max(1, Int(sampleRate * 0.4)) // removes content faster than ~2.5 Hz
        let detrended = highPass(raw, window: highPassWindow)
        let bandPassed = movingAverage(detrended, window: lowPassWindow)

        // Average movement magnitude (radians) within the breathing band — the core of the
        // stillness score, and a useful readout in movement mode too.
        let movementRMS = rootMeanSquare(bandPassed)

        // One breath can't be faster than ~50/min → enforce a minimum peak spacing.
        let minDistance = Int(sampleRate * 1.2)
        let peaks = findPeaks(bandPassed, minDistance: minDistance)

        // Rate + variability need at least a couple of breaths to be meaningful.
        // (2 lets short ~10 s sessions produce a score; rhythm variability is weak with so
        // few intervals, so the score leans on amplitude regularity until more breaths exist.)
        let minBreathsForScore = 2
        var bpm = 0.0, intervalCV = 0.0, amplitudeCV = 0.0
        if peaks.count >= minBreathsForScore {
            let peakTimes = peaks.map { Double($0) / sampleRate }
            let intervals = zip(peakTimes.dropFirst(), peakTimes).map { $0 - $1 }
            let meanInterval = mean(intervals)
            bpm = meanInterval > 0 ? 60.0 / meanInterval : 0
            intervalCV = coefficientOfVariation(intervals)
            amplitudeCV = coefficientOfVariation(peaks.map { bandPassed[$0] })
        }

        let score: Int
        switch mode {
        case .movement:
            if targetBPM > 0 {
                // Paced: how well the user tracked the guide path.
                score = followScore(user: bandPassed, times: samples.map { $0.time }, period: 60.0 / targetBPM, sampleRate: sampleRate)
            } else {
                // Free-form: reward a steady, even sinusoid.
                score = peaks.count >= minBreathsForScore ? consistencyScore(intervalCV: intervalCV, amplitudeCV: amplitudeCV) : 0
            }
        case .stillness:
            score = stillnessScore(movementRMS: movementRMS)
        }

        return metrics(
            bpm: bpm,
            count: peaks.count,
            intervalCV: intervalCV,
            amplitudeCV: amplitudeCV,
            movementRMS: movementRMS,
            score: score
        )
    }

    // MARK: - Scoring

    /// Free-form Movement (no target pace): reward a regular sinusoid. Rhythm weighted over depth.
    private func consistencyScore(intervalCV: Double, amplitudeCV: Double) -> Int {
        let intervalRegularity = max(0, 1 - min(intervalCV, 0.6) / 0.6)
        let amplitudeRegularity = max(0, 1 - min(amplitudeCV, 0.8) / 0.8)
        let score = 100 * (0.65 * intervalRegularity + 0.35 * amplitudeRegularity)
        return Int(score.rounded())
    }

    /// Movement mode: how well the user's waveform tracks the paced guide.
    ///
    /// Correlates the (normalized) user signal against the target sine over a range of small
    /// time lags — so a steady reaction delay isn't penalized — and takes the best positive
    /// correlation. 1.0 → perfectly on the path, ≤0 → unrelated or anti-phase.
    private func followScore(user: [Double], times: [Double], period: Double, sampleRate: Double) -> Int {
        guard user.count > Int(sampleRate * 3), user.count == times.count else { return 0 }
        let u = zScore(user)
        let g = zScore(times.map { BreathingGuide.value(at: $0, period: period) })

        let maxLag = Int(period * sampleRate)          // up to one full breath cycle
        let step = max(1, maxLag / 40)                  // cap the lag search cost
        var best = 0.0
        var lag = 0
        while lag <= maxLag {
            best = max(best, laggedCorrelation(u, g, lag: lag))
            lag += step
        }
        return Int((max(0, best) * 100).rounded())
    }

    /// Stillness mode: less movement → higher score. `k` is the "quiet" RMS scale in radians
    /// (≈1.7°); it likely needs tuning against real device data.
    private func stillnessScore(movementRMS: Double) -> Int {
        let k = 0.03
        let score = 100 * exp(-movementRMS / k)
        return Int(min(100, max(0, score)).rounded())
    }

    // MARK: - DSP helpers

    private func movingAverage(_ x: [Double], window: Int) -> [Double] {
        guard window > 1, x.count >= window else { return x }
        var out = [Double](repeating: 0, count: x.count)
        let half = window / 2
        // Prefix sums for an O(n) centered moving average.
        var prefix = [Double](repeating: 0, count: x.count + 1)
        for i in 0..<x.count { prefix[i + 1] = prefix[i] + x[i] }
        for i in 0..<x.count {
            let lo = max(0, i - half)
            let hi = min(x.count, i + half + 1)
            out[i] = (prefix[hi] - prefix[lo]) / Double(hi - lo)
        }
        return out
    }

    /// High-pass = signal minus its long moving average.
    private func highPass(_ x: [Double], window: Int) -> [Double] {
        let baseline = movingAverage(x, window: window)
        return zip(x, baseline).map { $0 - $1 }
    }

    /// Local maxima above zero, thinned so no two peaks are closer than `minDistance`.
    private func findPeaks(_ x: [Double], minDistance: Int) -> [Int] {
        guard x.count > 2 else { return [] }
        var candidates: [Int] = []
        for i in 1..<(x.count - 1) where x[i] > x[i - 1] && x[i] >= x[i + 1] && x[i] > 0 {
            candidates.append(i)
        }
        // Greedily keep the tallest peaks first, dropping any too close to an accepted one.
        var accepted: [Int] = []
        for idx in candidates.sorted(by: { x[$0] > x[$1] }) {
            if accepted.allSatisfy({ abs($0 - idx) >= minDistance }) {
                accepted.append(idx)
            }
        }
        return accepted.sorted()
    }

    // MARK: - Stats

    private func mean(_ x: [Double]) -> Double {
        guard !x.isEmpty else { return 0 }
        return x.reduce(0, +) / Double(x.count)
    }

    private func standardDeviation(_ x: [Double]) -> Double {
        guard x.count > 1 else { return 0 }
        let m = mean(x)
        let variance = x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)
        return variance.squareRoot()
    }

    private func coefficientOfVariation(_ x: [Double]) -> Double {
        let m = abs(mean(x))
        guard m > 1e-9 else { return 0 }
        return standardDeviation(x) / m
    }

    private func rootMeanSquare(_ x: [Double]) -> Double {
        guard !x.isEmpty else { return 0 }
        let sumSquares = x.reduce(0) { $0 + $1 * $1 }
        return (sumSquares / Double(x.count)).squareRoot()
    }

    /// Zero mean, unit standard deviation. Flat input → all zeros.
    private func zScore(_ x: [Double]) -> [Double] {
        let m = mean(x)
        let sd = standardDeviation(x)
        guard sd > 1e-9 else { return [Double](repeating: 0, count: x.count) }
        return x.map { ($0 - m) / sd }
    }

    /// Mean product of two z-scored signals with `b` shifted earlier by `lag` samples
    /// (≈ Pearson correlation at that lag).
    private func laggedCorrelation(_ a: [Double], _ b: [Double], lag: Int) -> Double {
        let n = a.count
        guard lag < n else { return 0 }
        var sum = 0.0
        var count = 0
        var i = lag
        while i < n {
            sum += a[i] * b[i - lag]
            count += 1
            i += 1
        }
        return count > 0 ? sum / Double(count) : 0
    }
}
