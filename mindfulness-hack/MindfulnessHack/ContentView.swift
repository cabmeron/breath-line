import SwiftUI

struct ContentView: View {
    @StateObject private var session = BreathingSession()
    @EnvironmentObject private var store: SessionStore

    @State private var mode: MeasurementMode = .movement
    @State private var durationSeconds: Double = 60
    @State private var targetBPM: Double = 6
    @State private var targetPaceEnabled = true
    @State private var vibrationEnabled = false
    @State private var showingSessions = false
    @State private var didSaveCurrent = false

    private let durationOptions: [Double] = [10, 30, 60, 120, 180]

    var body: some View {
        NavigationStack {
            Group {
                switch session.state {
                case .idle:      setupView
                case .recording: recordingView
                case .finished:  resultsView
                }
            }
            .padding()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if session.state != .recording {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSessions = true
                        } label: {
                            Label("Saved sessions", systemImage: "list.bullet.rectangle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSessions) {
                SessionListView()
            }
        }
    }

    // MARK: - Setup

    private var setupView: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "wind")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Train your breath.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Pick a goal, rest the phone on that spot, and breathe.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Goal").font(.subheadline.weight(.semibold))
                ForEach(MeasurementMode.allCases) { option in
                    modeRow(option)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Target pace", isOn: $targetPaceEnabled)
                    .font(.subheadline.weight(.semibold))

                VStack(spacing: 14) {
                    Stepper(value: $targetBPM, in: 3...20, step: 1) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(targetBPM)) breaths / min")
                                .font(.body.weight(.medium))
                            Text(String(format: "%.1fs in · %.1fs out", 30 / targetBPM, 30 / targetBPM))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    Toggle(isOn: $vibrationEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Vibrate off path").font(.body.weight(.medium))
                            Text("Buzzes harder the farther you stray")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(!targetPaceEnabled)
                .opacity(targetPaceEnabled ? 1 : 0.4)
            }
            // Only meaningful in Movement mode — kept visible but disabled so the layout
            // doesn't shift when switching goals.
            .disabled(mode != .movement)
            .opacity(mode == .movement ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 12) {
                Text("Duration").font(.subheadline.weight(.semibold))
                Picker("Duration", selection: $durationSeconds) {
                    ForEach(durationOptions, id: \.self) { secs in
                        Text(durationLabel(secs)).tag(secs)
                    }
                }
                .pickerStyle(.segmented)
            }

            Spacer()

            if session.isMotionAvailable {
                Button {
                    didSaveCurrent = false
                    let bpmToUse = (mode == .movement && targetPaceEnabled) ? targetBPM : 0
                    session.start(duration: durationSeconds, mode: mode, targetBPM: bpmToUse, vibrate: vibrationEnabled)
                } label: {
                    Text("Start session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Label("Motion sensors are unavailable on this device.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modeRow(_ option: MeasurementMode) -> some View {
        Button {
            mode = option
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.systemImage)
                    .font(.title2)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.body.weight(.medium))
                    Text(option.tagline).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: mode == option ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(mode == option ? Color.accentColor : Color.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recording

    private var recordingView: some View {
        VStack(spacing: 28) {
            Spacer()

            Text(timeString(session.remaining))
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            BreathingWaveformView(samples: session.liveWaveform, guide: session.liveGuide)
                .frame(height: 160)

            HStack(spacing: 40) {
                metric("Breaths", value: "\(session.liveBreathCount)")
                metric("Elapsed", value: timeString(session.elapsed))
            }

            Text(mode.instruction)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button(role: .destructive) {
                session.cancel()
            } label: {
                Text("Stop").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Results

    private var resultsView: some View {
        let m = session.metrics
        return VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 6) {
                Text("\(m.score)")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
                Text(m.scoreCaption).font(.subheadline).foregroundStyle(.secondary)
                Text(m.qualitativeRating).font(.headline)
            }

            BreathingWaveformView(samples: session.liveWaveform, guide: session.liveGuide)
                .frame(height: 120)

            MetricsCard(metrics: m)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    saveCurrentSession()
                } label: {
                    Label(didSaveCurrent ? "Saved" : "Save session",
                          systemImage: didSaveCurrent ? "checkmark" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(didSaveCurrent)

                Button {
                    session.reset()
                } label: {
                    Text("Done").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func saveCurrentSession() {
        guard !didSaveCurrent else { return }
        let saved = SavedSession(
            date: Date(),
            mode: session.lastMode,
            durationSeconds: session.metrics.durationSeconds,
            sampleRate: session.sampleRate,
            metrics: session.metrics,
            samples: session.recordedSamples
        )
        store.add(saved)
        didSaveCurrent = true
    }

    // MARK: - Small subviews / helpers

    private func metric(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func durationLabel(_ seconds: Double) -> String {
        seconds < 60 ? "\(Int(seconds))s" : "\(Int(seconds / 60))m"
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionStore())
}
