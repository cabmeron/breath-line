# Mindfulness Hack

A SwiftUI iOS app that measures **how consistent your breathing is** over a timed session.
Lie down, rest the phone flat on your **chest** or **stomach**, and the app reads the rise
and fall from Core Motion, shows a live waveform, and scores the rhythm's steadiness.

See **[SENSOR_PLAN.md](SENSOR_PLAN.md)** for the sensor rationale and signal pipeline.

## Run it

1. Open `MindfulnessHack.xcodeproj` in Xcode 16+.
2. Select your team under **Signing & Capabilities** (the bundle id is
   `com.mindfulnesshack.app` — change it if needed).
3. Build to a **real device** — the Simulator has no motion sensors, so the waveform stays
   flat there.
4. Lie down, place the phone on your chest/belly, pick a duration, and tap **Start session**.

The project uses Xcode 16 **file-system-synchronized groups**, so every `.swift` file in the
`MindfulnessHack/` folder is compiled automatically — no need to add files to the target by
hand.

## Source layout

| File | Role |
|---|---|
| `MindfulnessHackApp.swift` | App entry point |
| `Models.swift` | `BreathingPlacement`, `BreathSample`, `BreathingMetrics` |
| `BreathingSession.swift` | Core Motion capture loop + live breath counter |
| `SignalProcessor.swift` | Band-pass, peak detection, rate / CV / score |
| `BreathingWaveformView.swift` | Live waveform rendering |
| `ContentView.swift` | Setup → recording → results UI |

## What it measures

- **Breathing rate** (breaths/min)
- **Rhythm variability** — coefficient of variation of breath-to-breath intervals
- **Depth variability** — coefficient of variation of breath amplitudes
- **Consistency score** (0–100) combining the two, rhythm weighted higher

## Not yet wired in (natural next steps)

- **Barometer** (`CMAltimeter`) as a complementary vertical-lift signal.
- **HealthKit** logging (mindful minutes + respiratory rate).
- A proper **Butterworth band-pass** via `Accelerate`/`vDSP` in place of the moving-average
  filters used in the prototype.
