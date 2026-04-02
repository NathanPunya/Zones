import CoreLocation
import Foundation

/// Suggests loop routes: the difficulty slider controls **loop radius** (short/easy → long/hard) and **orientation** so the path changes on screen.
/// Perimeter points are snapped via Google Directions from **your location** (start/end); `fallbackDense` is used if Directions fails.
struct RouteSuggestionEngine {
    /// Slider range for difficulty; maps to loop radius between engine min/max (whole numbers only in UI).
    static let difficultySliderMin = 1.0
    static let difficultySliderMax = 50.0
    static var difficultySliderRange: ClosedRange<Double> {
        difficultySliderMin...difficultySliderMax
    }

    /// Upper bound on loop radius (meters). Larger → bigger suggested area.
    private static let radiusCapMeters = 50_000.0
    /// Minimum value for the slider’s **max** radius. Without this, `maxRadius` was almost entirely
    /// `avgDistance * avgDistanceRadiusFactor`, so raising `radiusCapMeters` had no visible effect.
    private static let sliderMaxRadiusFloorMeters = 25_000.0
    /// Scales how far `avgDistance` from HealthKit can push the max radius (was 0.42).
    private static let avgDistanceRadiusFactor = 0.95
    /// When there are no recent runs, assume this typical distance (meters) for scaling.
    private static let defaultAvgRunDistanceMeters = 8000.0
    struct Suggestion: Identifiable {
        let id = UUID()
        /// GPS anchor: Directions round-trip starts and ends here.
        let userLocation: CLLocationCoordinate2D
        /// Intermediate stops on the loop (optimized order). Does not include `userLocation`.
        let loopWaypoints: [CLLocationCoordinate2D]
        let fallbackDense: [CLLocationCoordinate2D]
        let difficulty: Double
        let sliderLevel: Double
        let targetRadiusMeters: Double
        let score: Double
        let tierLabel: String
    }

    func suggest(
        center: CLLocationCoordinate2D,
        existingZones: [ZoneRecord],
        recentRunDistances: [Double],
        desiredDifficulty: Double,
        surfacePreference: RouteSurfacePreference,
        extraAngleRadians: Double = 0
    ) -> [Suggestion] {
        let avgDistance = recentRunDistances.isEmpty
            ? Self.defaultAvgRunDistanceMeters
            : recentRunDistances.reduce(0, +) / Double(recentRunDistances.count)

        // Slider maps linearly to radius between computed min and max (capped for API / sanity).
        let span = Self.difficultySliderMax - Self.difficultySliderMin
        let t = (desiredDifficulty - Self.difficultySliderMin) / span
        let minRadius = max(80, avgDistance * 0.08)
        let maxRadius = min(
            Self.radiusCapMeters,
            max(
                minRadius + 200,
                avgDistance * Self.avgDistanceRadiusFactor,
                Self.sliderMaxRadiusFloorMeters
            )
        )
        let radius = minRadius + t * (maxRadius - minRadius)

        // Spin the triangle as the slider moves so Directions picks different street segments.
        // `extraAngleRadians` is used when retrying to reduce covering the same corridors twice.
        let angleOffset = t * 5 * Double.pi + extraAngleRadians

        let occupied = existingZones.map(\.polygon).map { $0.map(\.coordinate) }
        let cand = makeSingleCandidate(
            center: center,
            radiusMeters: radius,
            angleOffset: angleOffset,
            surfacePreference: surfacePreference
        )

        let difficulty = estimateDifficulty(loop: cand.dense, center: center, occupiedPolygons: occupied)
        let score = scoreCandidate(
            difficulty: difficulty,
            desired: desiredDifficulty,
            loop: cand.dense,
            occupiedPolygons: occupied
        )
        let tier = Self.tierLabel(forSliderLevel: desiredDifficulty)
        return [
            Suggestion(
                userLocation: cand.userLocation,
                loopWaypoints: cand.loopWaypoints,
                fallbackDense: cand.dense,
                difficulty: difficulty,
                sliderLevel: desiredDifficulty,
                targetRadiusMeters: radius,
                score: score,
                tierLabel: tier
            )
        ]
    }

    private struct CandidateLoop {
        let userLocation: CLLocationCoordinate2D
        let loopWaypoints: [CLLocationCoordinate2D]
        let dense: [CLLocationCoordinate2D]
    }

    private func makeSingleCandidate(
        center: CLLocationCoordinate2D,
        radiusMeters: Double,
        angleOffset: Double,
        surfacePreference: RouteSurfacePreference
    ) -> CandidateLoop {
        let degPerMeterLat = 1.0 / 111_320.0
        let n = surfacePreference.perimeterWaypointCount
        var loopWaypoints: [CLLocationCoordinate2D] = []
        for k in 0..<n {
            let t = Double(k) / Double(n) * 2 * .pi + angleOffset
            let lat = center.latitude + cos(t) * radiusMeters * degPerMeterLat
            let lon = center.longitude + sin(t) * radiusMeters * degPerMeterLat / cos(center.latitude * .pi / 180)
            loopWaypoints.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        let dense = makeDenseCircle(center: center, radiusMeters: radiusMeters, angleOffset: angleOffset, steps: 10)
        return CandidateLoop(userLocation: center, loopWaypoints: loopWaypoints, dense: dense)
    }

    private func makeDenseCircle(center: CLLocationCoordinate2D, radiusMeters: Double, angleOffset: Double, steps: Int) -> [CLLocationCoordinate2D] {
        let degPerMeterLat = 1.0 / 111_320.0
        var pts: [CLLocationCoordinate2D] = []
        for s in 0...steps {
            let t = Double(s) / Double(steps) * 2 * .pi + angleOffset
            let lat = center.latitude + cos(t) * radiusMeters * degPerMeterLat
            let lon = center.longitude + sin(t) * radiusMeters * degPerMeterLat / cos(center.latitude * .pi / 180)
            pts.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        return pts
    }

    private func estimateDifficulty(
        loop: [CLLocationCoordinate2D],
        center: CLLocationCoordinate2D,
        occupiedPolygons: [[CLLocationCoordinate2D]]
    ) -> Double {
        let area = ZoneGeometry.areaSquareMeters(polygon: loop)
        let perimeter = ZoneGeometry.pathLengthMeters(loop)
        let overlapPenalty = occupiedPolygons.reduce(0.0) { partial, poly in
            partial + overlapRatio(loop: loop, other: poly)
        }
        let compact = perimeter > 0 ? area / (perimeter * perimeter) : 0
        return (area / 10_000) * (1 + overlapPenalty) + (1 - min(1, compact * 5))
    }

    private func overlapRatio(loop: [CLLocationCoordinate2D], other: [CLLocationCoordinate2D]) -> Double {
        guard let c = loop.first, let box = ZoneGeometry.boundingBox(for: other) else { return 0 }
        let p = c
        let inside = (p.latitude >= box.min.latitude && p.latitude <= box.max.latitude
            && p.longitude >= box.min.longitude && p.longitude <= box.max.longitude)
        return inside ? 0.4 : 0
    }

    private func scoreCandidate(
        difficulty: Double,
        desired: Double,
        loop: [CLLocationCoordinate2D],
        occupiedPolygons: [[CLLocationCoordinate2D]]
    ) -> Double {
        let diffTerm = abs(difficulty - desired)
        let overlap = occupiedPolygons.reduce(0.0) { $0 + overlapRatio(loop: loop, other: $1) }
        return diffTerm * 2 + overlap * 10
    }

    /// Tier copy for a slider value (same thresholds as route generation).
    static func tierLabel(forSliderLevel sliderLevel: Double) -> String {
        let span = Self.difficultySliderMax - Self.difficultySliderMin
        // Thresholds match former 2.5 / 4 on a 0.5…6 scale, scaled to current min…max (fixed numerators from legacy 0.5 baseline).
        let easierBelow = Self.difficultySliderMin + (2.5 - 0.5) / 5.5 * span
        let harderAbove = Self.difficultySliderMin + (4.0 - 0.5) / 5.5 * span
        if sliderLevel < easierBelow { return "Easier (shorter)" }
        if sliderLevel > harderAbove { return "Harder (longer)" }
        return "Moderate"
    }
}
