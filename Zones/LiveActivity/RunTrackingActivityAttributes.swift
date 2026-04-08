import ActivityKit
import Foundation

/// Shared between the app (starts/updates the activity) and the widget extension (UI).
struct RunTrackingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var distanceMeters: Double
        var durationSeconds: Int
        var loopClosed: Bool
    }
}
