import Foundation

/// The ideal breathing curve the user follows in `.paced` mode.
enum BreathingGuide {
    /// Normalized target position in [-1, 1] at time `t` for a breath cycle of `period` seconds.
    /// Rises through 0 at t=0 (inhale), peaks at quarter-period, troughs at three-quarters.
    static func value(at t: TimeInterval, period: TimeInterval) -> Double {
        guard period > 0 else { return 0 }
        return sin(2 * .pi * t / period)
    }
}

/// What the user is trying to achieve at the spot where the phone rests.
///
/// Capture and signal extraction are identical for both modes — a detrended tilt waveform.
/// Only the *scoring* differs:
///   - `.movement`  rewards a clean, steady sinusoidal rise & fall (e.g. the belly during
///                  diaphragmatic breathing).
///   - `.stillness` rewards minimal motion (e.g. the chest, which should stay quiet while
///                  you breathe from the diaphragm).
enum MeasurementMode: String, CaseIterable, Identifiable, Codable {
    case movement
    case stillness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movement:  return "Movement"
        case .stillness: return "Stillness"
        }
    }

    var tagline: String {
        switch self {
        case .movement:  return "Follow a paced breathing path"
        case .stillness: return "Keep this spot as still as possible"
        }
    }

    var instruction: String {
        switch self {
        case .movement:
            return "Rest the phone where you breathe (e.g. your belly). Breathe in as the dashed guide rises and out as it falls — try to match it."
        case .stillness:
            return "Rest the phone where you want to stay quiet (e.g. your chest). Breathe from your belly and keep this spot still."
        }
    }

    var systemImage: String {
        switch self {
        case .movement:  return "waveform.path.ecg"
        case .stillness: return "circle.dotted"
        }
    }
}

/// One point of the respiration waveform.
struct BreathSample: Codable, Equatable {
    /// Seconds since the start of the session.
    let time: TimeInterval
    /// Detrended tilt signal (radians) — the breathing waveform.
    let value: Double
}

/// Results computed at the end of a session.
struct BreathingMetrics: Equatable, Codable {
    let mode: MeasurementMode
    let breathsPerMinute: Double
    let breathCount: Int
    /// Coefficient of variation of breath-to-breath intervals. Lower = steadier rhythm.
    let intervalCV: Double
    /// Coefficient of variation of breath depths.
    let amplitudeCV: Double
    /// Average breathing-band movement magnitude, in radians of tilt.
    let movementRMS: Double
    /// Target pace (breaths/min) the user was following in `.movement` mode (0 otherwise).
    let targetBPM: Double
    /// 0...100. Meaning depends on `mode` (path-following accuracy vs. stillness).
    let score: Int
    let durationSeconds: Double

    static let empty = BreathingMetrics(
        mode: .movement,
        breathsPerMinute: 0,
        breathCount: 0,
        intervalCV: 0,
        amplitudeCV: 0,
        movementRMS: 0,
        targetBPM: 0,
        score: 0,
        durationSeconds: 0
    )

    /// Average movement expressed in degrees (friendlier than radians for display).
    var movementDegrees: Double { movementRMS * 180 / .pi }

    /// True when a paced guide path was active (Movement mode with a target pace).
    var isPaced: Bool { mode == .movement && targetBPM > 0 }

    var scoreCaption: String {
        switch mode {
        case .movement:  return isPaced ? "Follow accuracy" : "Consistency score"
        case .stillness: return "Stillness score"
        }
    }

    var qualitativeRating: String {
        switch mode {
        case .movement where isPaced:
            switch score {
            case 85...100: return "Excellent — right on the path"
            case 70..<85:  return "Good — close to the path"
            case 50..<70:  return "Fair — drifting off"
            case 1..<50:   return "Off the path — keep trying"
            default:       return "Not enough data"
            }
        case .movement:
            switch score {
            case 85...100: return "Excellent — very steady"
            case 70..<85:  return "Good — fairly steady"
            case 50..<70:  return "Fair — some drift"
            case 1..<50:   return "Uneven — keep practicing"
            default:       return "Not enough data"
            }
        case .stillness:
            switch score {
            case 85...100: return "Excellent — very still"
            case 70..<85:  return "Good — mostly still"
            case 50..<70:  return "Fair — some movement"
            case 1..<50:   return "Lots of movement"
            default:       return "Not enough data"
            }
        }
    }
}
