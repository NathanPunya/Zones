import SwiftUI

/// Collapsed: narrow banner with essentials. Expanded: full metrics (tap chevron).
struct RouteInsightCard: View {
    let insight: RouteInsight
    let pathDistanceMeters: Double
    let isLoading: Bool

    @Environment(\.measurementUnits) private var measurementUnits
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bannerStrip

            if isExpanded {
                expandedDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.22), value: isExpanded)
        .onChange(of: isLoading) { _, loading in
            if loading {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                }
            }
        }
    }

    /// Collapsed summary strip with extra vertical padding so it does not feel cramped.
    private var bannerStrip: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "map")
                .font(.body.weight(.medium))
                .foregroundStyle(.orange)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("Suggested loop")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Group {
                    if isLoading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Updating…")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(formatDistance(pathDistanceMeters))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text(formatArea(insight.enclosedAreaSquareMeters))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text("Lv \(String(format: "%.0f", insight.level))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.orange.gradient, in: Capsule())
                            }
                            Text(UnitsFormat.routeWalkRunEstimateLabel(pathMeters: pathDistanceMeters))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isExpanded ? "Hide route details" : "Show route details")
            .disabled(isLoading)
            .opacity(isLoading ? 0.35 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.horizontal, -4)

            Text("\(insight.tierLabel) · target size ~\(UnitsFormat.targetRadius(meters: Double(insight.targetRadiusMeters), units: measurementUnits))")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Along streets")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(formatDistance(pathDistanceMeters))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(UnitsFormat.routeWalkRunEstimateLabel(pathMeters: pathDistanceMeters))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text("Assumes ~5 km/h walking and ~10 km/h running (easy pace). Times of one hour or more use decimal hours.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                metricPill(title: "Area (loop)", value: formatArea(insight.enclosedAreaSquareMeters))
                metricPill(title: "Score", value: String(format: "%.0f", insight.score))
                metricPill(title: "Challenge", value: String(format: "%.0f", insight.challengeMetric))
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: insight.pathKind == .streetSnapped ? "checkmark.circle.fill" : "map.circle")
                    .font(.caption)
                    .foregroundStyle(insight.pathKind == .streetSnapped ? .green : .orange)
                Text(insight.pathKind == .streetSnapped
                    ? "Snapped to walking paths (Google Directions)"
                    : "Circle preview — enable Directions API for street paths")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 4)
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .tracking(0.4)
            Text(value)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func formatDistance(_ m: Double) -> String {
        UnitsFormat.distance(meters: m, units: measurementUnits)
    }

    private func formatArea(_ m2: Double) -> String {
        UnitsFormat.area(squareMeters: m2, units: measurementUnits)
    }
}

#Preview {
    RouteInsightCard(
        insight: RouteInsight(
            level: 5.3,
            tierLabel: "Harder (longer)",
            targetRadiusMeters: 930,
            score: 499.6,
            challengeMetric: 255.1,
            pathKind: .streetSnapped,
            enclosedAreaSquareMeters: 1_850_000
        ),
        pathDistanceMeters: 5770,
        isLoading: false
    )
    .environment(\.measurementUnits, .metric)
    .padding()
}
