import ActivityKit
import SwiftUI
import WidgetKit

private func distanceString(_ meters: Double) -> String {
    if meters >= 1000 {
        return String(format: "%.2f km", meters / 1000)
    }
    return String(format: "%.0f m", meters)
}

private func shortDistance(_ meters: Double) -> String {
    if meters >= 1000 {
        return String(format: "%.1fk", meters / 1000)
    }
    return String(format: "%.0fm", meters)
}

private func durationString(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return String(format: "%d:%02d", m, s)
}

/// Lock screen / banner (device locked or not in foreground Island).
private enum LockScreenLayout {
    static let horizontal: CGFloat = 16
    static let vertical: CGFloat = 12
}

/// Dynamic Island (unlocked phone, foreground).
private enum IslandLayout {
    static let expandedHorizontal: CGFloat = 12
    static let expandedVertical: CGFloat = 6
    static let bottomExtraHorizontal: CGFloat = 4
    static let bottomExtraBottom: CGFloat = 6
    static let compactHorizontal: CGFloat = 3
    static let minimalInset: CGFloat = 2
}

struct RunTrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunTrackingActivityAttributes.self) { context in
            lockScreenBanner(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Zones", systemImage: "figure.run")
                        .font(.headline)
                        .padding(.leading, IslandLayout.expandedHorizontal)
                        .padding(.vertical, IslandLayout.expandedVertical)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(durationString(context.state.durationSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.trailing, IslandLayout.expandedHorizontal)
                        .padding(.vertical, IslandLayout.expandedVertical)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(distanceString(context.state.distanceMeters))
                            .font(.title2.weight(.semibold))
                        if context.state.loopClosed {
                            Text("Loop closed — claim your zone")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        } else {
                            Text("Run in progress")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, IslandLayout.expandedHorizontal + IslandLayout.bottomExtraHorizontal)
                    .padding(.bottom, IslandLayout.bottomExtraBottom)
                    .padding(.top, IslandLayout.expandedVertical)
                }
            } compactLeading: {
                Image(systemName: "figure.run")
                    .padding(.leading, IslandLayout.compactHorizontal)
            } compactTrailing: {
                Text(shortDistance(context.state.distanceMeters))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .padding(.trailing, IslandLayout.compactHorizontal)
            } minimal: {
                Image(systemName: "figure.run")
                    .padding(IslandLayout.minimalInset)
            }
        }
    }

    @ViewBuilder
    private func lockScreenBanner(state: RunTrackingActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundStyle(.orange)
                Text("Run in progress")
                    .font(.headline)
                Spacer()
                Text(durationString(state.durationSeconds))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(distanceString(state.distanceMeters))
                .font(.title2.weight(.semibold))
            if state.loopClosed {
                Text("Loop closed — claim your zone")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, LockScreenLayout.horizontal)
        .padding(.vertical, LockScreenLayout.vertical)
    }
}
