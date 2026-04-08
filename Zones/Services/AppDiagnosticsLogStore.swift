import Foundation

/// Session log for Google API / routing diagnostics (Settings → Logs).
@MainActor
final class AppDiagnosticsLogStore: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let title: String
        let message: String

        init(id: UUID = UUID(), date: Date = Date(), title: String, message: String) {
            self.id = id
            self.date = date
            self.title = title
            self.message = message
        }
    }

    @Published private(set) var entries: [Entry] = []
    /// Entries not yet opened in Settings → Logs (badge count).
    @Published private(set) var unseenEntryCount: Int = 0

    func logGoogleDirectionsFallback(_ detail: String) {
        let text = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        entries.insert(
            Entry(
                title: "Google Directions",
                message: text
            ),
            at: 0
        )
        unseenEntryCount += 1
    }

    func markAllLogsViewed() {
        unseenEntryCount = 0
    }
}
