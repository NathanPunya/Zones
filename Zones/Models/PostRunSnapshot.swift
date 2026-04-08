import CoreLocation
import Foundation

/// Captured when the user stops a run, before clearing the map — used for the capture sheet and optional zone claim.
@MainActor
struct PostRunSnapshot: Identifiable {
    let id = UUID()
    let polygon: [CLLocationCoordinate2D]
    let distanceMeters: Double
    let areaSquareMeters: Double
    let pointCount: Int
    let loopClosed: Bool
    let startedAt: Date?
    let endedAt: Date

    var durationSeconds: Int {
        guard let s = startedAt else { return 0 }
        return max(0, Int(endedAt.timeIntervalSince(s)))
    }

    /// Same scoring bump as `MemoryTerritorySyncService.claimZone` (demo / local sync).
    var estimatedWeeklyScoreGain: Int {
        max(1, Int(areaSquareMeters / 100))
    }

    /// Matches `MainMapViewModel.claimLoop` difficulty input.
    var territoryDifficulty: Double {
        max(0.5, areaSquareMeters / 5000)
    }

    var eligibleForZoneCapture: Bool {
        loopClosed && polygon.count >= 4 && areaSquareMeters > 0
    }

    init(runTracker: RunTrackingService, endedAt: Date) {
        self.polygon = runTracker.runPoints
        self.distanceMeters = runTracker.distanceMeters
        self.areaSquareMeters = runTracker.enclosedAreaSquareMeters ?? 0
        self.pointCount = runTracker.runPoints.count
        self.loopClosed = runTracker.loopClosed
        self.startedAt = runTracker.runStartedAt
        self.endedAt = endedAt
    }
}

enum RunOverviewFormat {
    static func duration(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
