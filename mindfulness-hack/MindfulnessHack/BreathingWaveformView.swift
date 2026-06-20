import SwiftUI

/// Draws the recent breathing waveform.
///
/// Scaling auto-fits to the signal but never below `minScale` (radians of tilt). The floor
/// is what keeps a near-still phone reading as a flat line at center instead of amplifying
/// sensor noise to fill the view.
struct BreathingWaveformView: View {
    let samples: [Double]
    /// Optional normalized [-1, 1] guide path drawn as a dashed line at a fixed amplitude.
    var guide: [Double] = []
    var minScale: Double = 0.05   // ≈ 2.9° — below this, motion shows as essentially flat

    var body: some View {
        Canvas { context, size in
            guard samples.count > 1 else { return }

            let maxAbs = max(samples.map { abs($0) }.max() ?? minScale, minScale)
            let midY = size.height / 2
            let stepX = size.width / CGFloat(samples.count - 1)

            // Zero baseline.
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: midY))
            baseline.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(baseline, with: .color(.secondary.opacity(0.25)), lineWidth: 1)

            // Guide path (fixed amplitude, drawn under the user's waveform).
            if guide.count > 1 {
                let gStep = size.width / CGFloat(guide.count - 1)
                var gpath = Path()
                for (i, v) in guide.enumerated() {
                    let x = CGFloat(i) * gStep
                    let y = midY - CGFloat(v) * (size.height * 0.40)
                    if i == 0 { gpath.move(to: CGPoint(x: x, y: y)) }
                    else { gpath.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(
                    gpath,
                    with: .color(.orange.opacity(0.8)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4])
                )
            }

            // Waveform.
            var path = Path()
            for (i, v) in samples.enumerated() {
                let x = CGFloat(i) * stepX
                let y = midY - CGFloat(v / maxAbs) * (size.height * 0.45)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(
                path,
                with: .color(.accentColor),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    BreathingWaveformView(
        samples: (0..<120).map { sin(Double($0) * 0.15) * 0.3 }
    )
    .frame(height: 160)
    .padding()
}
