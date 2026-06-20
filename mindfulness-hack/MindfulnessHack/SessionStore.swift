import Foundation

/// Persists saved sessions as a single JSON file in the app's Documents directory.
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [SavedSession] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("sessions.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        load()
    }

    func add(_ session: SavedSession) {
        sessions.insert(session, at: 0)   // newest first
        persist()
    }

    func delete(at offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        persist()
    }

    func delete(_ session: SavedSession) {
        sessions.removeAll { $0.id == session.id }
        persist()
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? decoder.decode([SavedSession].self, from: data) {
            sessions = decoded.sorted { $0.date > $1.date }
        }
    }

    private func persist() {
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
