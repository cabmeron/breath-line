# Mindfulness Hack — Sensor Plan

A Swift/SwiftUI iOS app that measures **how consistent a user's breathing is** over a
timed session. The user lies down, places the phone flat on their **chest** or **stomach**
(they pick which), and the app records the breathing waveform from motion sensors and
scores its regularity.

## How breathing reaches the phone

With the phone resting flat on the chest or abdomen, each breath does two things to it:

1. **Tilt** — the body surface changes angle a few degrees as it rises and falls.
   *This is the cleanest signal.*
2. **Translation** — the phone lifts ~1–3 cm per breath (larger on the belly with
   diaphragmatic breathing).

Breathing is slow — **0.1–0.5 Hz (≈6–30 breaths/min)** — which makes it easy to isolate
from higher-frequency noise.

## Sensor ranking

| Sensor | Framework / API | Use | Verdict |
|---|---|---|---|
| **Accelerometer + Gyroscope (fused)** | Core Motion → `CMMotionManager.deviceMotion` | Tilt/attitude = breathing waveform | **Primary.** Best signal, lowest noise |
| **Barometer** | Core Motion → `CMAltimeter` relative altitude | Detects the cm-scale vertical lift | **Secondary / experimental.** Sensitive but marginal at this amplitude — fuse it, don't rely on it |
| Microphone | AVFoundation | Breath sounds | **Skip.** Phone-on-belly won't capture breath audio reliably; hurts the privacy story |
| Camera / PPG | AVFoundation | — | **Skip.** Wrong placement entirely |

### Why `deviceMotion` and not raw accelerometer
`CMMotionManager` already runs Apple's sensor-fusion (accelerometer + gyro) and hands you a
drift-corrected **`gravity` vector** and **`attitude` (pitch/roll/yaw)**. The respiration
waveform is essentially `attitude.pitch` oscillating slowly. You get fused, low-noise data
for free instead of hand-rolling a filter over raw accelerometer + gyro samples.

## Signal pipeline

1. **Sample** `deviceMotion` at **30 Hz** (breathing needs only ~1 Hz by Nyquist, but
   headroom gives clean filtering).
2. **Calibrate** for the first ~10 s — capture resting orientation, remove the DC baseline.
3. **Band-pass** to 0.1–0.5 Hz to kill posture drift (high-pass) and jitter (low-pass).
   `Accelerate` / `vDSP` can do this with a proper Butterworth; the prototype uses
   moving-average high/low passes, which are robust and dependency-free.
4. **Extract cycles** — peak detection for breath timing; optionally a Welch PSD for the
   dominant respiratory frequency.

## Consistency metrics (the actual "hack")

- **Respiratory rate** (breaths/min)
- **Breath-interval CV** — coefficient of variation of breath-to-breath intervals;
  *lower = steadier rhythm* (the core metric)
- **Amplitude variability** — are breaths evenly deep?
- **Consistency score** — the above rolled into a single **0–100** value

## Practical notes

- **Chest vs. stomach toggle** mostly tunes expected amplitude/axis — belly breathing gives
  bigger excursion at the abdomen.
- Keep the session **foreground** and set `UIApplication.isIdleTimerDisabled = true` so the
  device doesn't sleep mid-session.
- **All on-device, no mic/camera** → strong privacy angle, which sells well for a
  mindfulness app.
- Optional: write the session to **HealthKit** (mindful minutes + respiratory rate).

## Stack

SwiftUI · Core Motion (`CMMotionManager`, `CMAltimeter`) · `Accelerate`/`vDSP` for DSP ·
optional HealthKit.

## What's in this prototype

The Xcode project in this folder implements the **primary path**: a 30 Hz `deviceMotion`
capture loop using `attitude.pitch`, live baseline removal, a live waveform view, a live
breath counter, and an end-of-session analysis (rate, interval CV, amplitude CV,
consistency score). The barometer and HealthKit hooks are described above but not yet wired
in — they're the natural next increments.
