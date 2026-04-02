import SwiftUI

struct LeaderboardView: View {
    let entries: [LeaderboardEntry]
    let currentUserId: String

    @Environment(\.measurementUnits) private var measurementUnits

    var body: some View {
        List {
            Section("Weekly score") {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Text("#\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.displayName)
                                .fontWeight(row.userId == currentUserId ? .bold : .regular)
                            Text("\(row.zonesCaptured) zones · \(UnitsFormat.distance(meters: row.totalDistanceMeters, units: measurementUnits)) total")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(row.weeklyScore)")
                                .font(.headline.monospacedDigit())
                            Text("\(row.streakDays)d streak")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.large)
    }
}
