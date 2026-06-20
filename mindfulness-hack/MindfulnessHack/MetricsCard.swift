import SwiftUI

/// A card of session stats. Which rows show depends on the measurement mode.
struct MetricsCard: View {
    let metrics: BreathingMetrics

    var body: some View {
        VStack(spacing: 0) {
            switch metrics.mode {
            case .movement where metrics.isPaced:
                row("Target pace", String(format: "%.0f /min", metrics.targetBPM))
                Divider()
                row("Your pace", String(format: "%.1f /min", metrics.breathsPerMinute))
                Divider()
                row("Breaths counted", "\(metrics.breathCount)")
                Divider()
                row("Rhythm variability", String(format: "%.0f%%", metrics.intervalCV * 100))
            case .movement:
                row("Breathing rate", String(format: "%.1f /min", metrics.breathsPerMinute))
                Divider()
                row("Breaths counted", "\(metrics.breathCount)")
                Divider()
                row("Rhythm variability", String(format: "%.0f%%", metrics.intervalCV * 100))
                Divider()
                row("Depth variability", String(format: "%.0f%%", metrics.amplitudeCV * 100))
            case .stillness:
                row("Avg movement", String(format: "%.2f°", metrics.movementDegrees))
                Divider()
                row("Breaths detected", "\(metrics.breathCount)")
                Divider()
                row("Breathing rate", String(format: "%.1f /min", metrics.breathsPerMinute))
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.weight(.medium)).monospacedDigit()
        }
        .padding()
    }
}
