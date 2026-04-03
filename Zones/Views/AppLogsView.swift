import SwiftUI

struct AppLogsView: View {
    @ObservedObject var logStore: AppDiagnosticsLogStore

    var body: some View {
        Group {
            if logStore.entries.isEmpty {
                ContentUnavailableView(
                    "No logs yet",
                    systemImage: "doc.text",
                    description: Text("If route generation falls back to a simple loop, details appear here.")
                )
            } else {
                List {
                    ForEach(logStore.entries) { entry in
                        Section {
                            Text(entry.message)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        } header: {
                            HStack {
                                Text(entry.title)
                                .font(.caption.weight(.semibold))
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text(entry.date, style: .date)
                                    .font(.caption)
                                Text(entry.date, style: .time)
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            logStore.markAllLogsViewed()
        }
    }
}

#Preview {
    NavigationStack {
        AppLogsView(logStore: AppDiagnosticsLogStore())
    }
}
