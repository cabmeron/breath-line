import SwiftUI

/// Presented as a sheet from the main screen: the user's saved sessions.
struct SessionListView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    ContentUnavailableView(
                        "No saved sessions",
                        systemImage: "wind",
                        description: Text("Finish a session and tap Save to see it here.")
                    )
                } else {
                    List {
                        ForEach(store.sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRow(session: session)
                            }
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("Saved Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: SavedSession

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 46, height: 46)
                Text("\(session.metrics.score)")
                    .font(.headline)
                    .foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(session.date, format: .dateTime.month().day().hour().minute())
                    .font(.body.weight(.medium))
                Text("\(session.mode.title) · \(detailText) · \(durationText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// Mode-appropriate middle detail: target pace for movement, movement amount for stillness.
    private var detailText: String {
        switch session.mode {
        case .movement where session.metrics.isPaced:
            return "\(Int(session.metrics.targetBPM)) bpm target"
        case .movement:
            return "\(Int(session.metrics.breathsPerMinute)) bpm"
        case .stillness:
            return String(format: "%.1f° move", session.metrics.movementDegrees)
        }
    }

    private var durationText: String {
        let secs = Int(session.durationSeconds)
        return secs < 60 ? "\(secs)s" : "\(secs / 60)m"
    }
}
