import SwiftUI

/// After stopping a run with a closed loop: stats + optional zone capture (replaces infinite manual “Claim”).
struct PostRunCaptureSheet: View {
    let snapshot: PostRunSnapshot
    var onCapture: () -> Void
    var onSkip: () -> Void

    @Environment(\.measurementUnits) private var measurementUnits

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        statTile(title: "Distance", value: UnitsFormat.distance(meters: snapshot.distanceMeters, units: measurementUnits), icon: "point.topleft.down.to.point.bottomright.curvepath")
                        statTile(title: "Time", value: RunOverviewFormat.duration(seconds: snapshot.durationSeconds), icon: "clock")
                        statTile(title: "Area enclosed", value: UnitsFormat.area(squareMeters: snapshot.areaSquareMeters, units: measurementUnits), icon: "square.dashed")
                        statTile(title: "GPS points", value: "\(snapshot.pointCount)", icon: "mappin.and.ellipse")
                        statTile(title: "Est. weekly score", value: "+\(snapshot.estimatedWeeklyScoreGain)", icon: "star.fill")
                        statTile(title: "Territory challenge", value: String(format: "%.1f", snapshot.territoryDifficulty), icon: "flame")
                    }

                    if snapshot.eligibleForZoneCapture {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Closed loop", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                            Text("Capture this zone to add it to the map and your leaderboard score.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding()
            }
            .navigationTitle("Run overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        onSkip()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if snapshot.eligibleForZoneCapture {
                        Button("Capture zone") {
                            onCapture()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func statTile(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
                .minimumScaleFactor(0.8)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
