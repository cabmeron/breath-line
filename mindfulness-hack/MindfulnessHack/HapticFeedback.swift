import CoreHaptics

/// A continuous haptic "buzz" whose intensity can be modulated in real time.
///
/// Used in paced Movement sessions: the farther the user's breathing strays from the guide
/// path, the stronger the vibration. Silent (intensity 0) when on the path.
final class HapticFeedback {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private(set) var isRunning = false

    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func start() {
        guard supportsHaptics, !isRunning else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = false
            // Restart the continuous player if the engine gets reset (e.g. after an interruption).
            engine.resetHandler = { [weak self] in
                guard let self else { return }
                try? self.engine?.start()
                try? self.player?.start(atTime: CHHapticTimeImmediate)
            }
            try engine.start()

            // One long continuous event at zero intensity; we drive intensity live.
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: 0,
                duration: 60 * 60
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)

            self.engine = engine
            self.player = player
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    /// Set the buzz strength, 0...1.
    func setIntensity(_ value: Double) {
        guard isRunning, let player else { return }
        let clamped = Float(max(0, min(1, value)))
        let param = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: clamped,
            relativeTime: 0
        )
        try? player.sendParameters([param], atTime: CHHapticTimeImmediate)
    }

    func stop() {
        guard isRunning else { return }
        try? player?.stop(atTime: CHHapticTimeImmediate)
        engine?.stop()
        player = nil
        engine = nil
        isRunning = false
    }
}
