import CoreLocation
import XCTest
@testable import Zones

/// Times **only** CPU work: `suggest()` + geometry helpers — **no HTTP**, **no debounce**, **not** comparable to tapping “New route” in the app.
///
/// On a real device, route gen is dominated by **Google Directions** (often ~0.5–4s+ per request) plus optional retries. Check **Settings → Logs → “Route timing”** after a run for true wall-clock numbers.
final class RouteGenLocalTimingTests: XCTestCase {
    func testLocalSuggestionAndGeometryLatencyPerLevel() {
        let engine = RouteSuggestionEngine()
        let center = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let zones: [ZoneRecord] = []
        let recent = [5_000.0, 8_000.0]
        let surface = RouteSurfacePreference.streetsAndSidewalks

        let levels = [1, 5, 10, 15, 20, 25]
        let reps = 40
        var lines: [String] = []

        let fakePath = (0..<90).map { i -> CLLocationCoordinate2D in
            let t = Double(i) * 0.00012
            return CLLocationCoordinate2D(latitude: center.latitude + t, longitude: center.longitude + t * 0.15)
        }

        for level in levels {
            let lv = Double(level)
            let tSuggest0 = CFAbsoluteTimeGetCurrent()
            for _ in 0..<reps {
                _ = engine.suggest(
                    center: center,
                    existingZones: zones,
                    recentRunDistances: recent,
                    desiredDifficulty: lv,
                    surfacePreference: surface
                )
            }
            let suggestMs = (CFAbsoluteTimeGetCurrent() - tSuggest0) * 1000 / Double(reps)

            let r = RouteSuggestionEngine.approximateLoopRadiusMeters(displayLevel: lv, recentRunDistances: recent)
            let deb = RouteSuggestionEngine.prefetchDebounceMilliseconds(approximateLoopRadiusMeters: r)
            let maxU = RouteSuggestionEngine.maxRouteUniquenessAttempts(approximateLoopRadiusMeters: r)
            let spur = RouteSuggestionEngine.maxSpurRefinementIterations(
                approximateLoopRadiusMeters: r,
                snappedPathLengthMeters: 4_500
            )

            let tGeom0 = CFAbsoluteTimeGetCurrent()
            for _ in 0..<reps {
                _ = ZoneGeometry.pathRetracesCorridor(path: fakePath, cellSizeMeters: 20)
                _ = ZoneGeometry.initialOutboundHeadingRadians(path: fakePath)
                _ = ZoneGeometry.polylineSignature(fakePath)
            }
            let geomMs = (CFAbsoluteTimeGetCurrent() - tGeom0) * 1000 / Double(reps)

            lines.append(
                "Lv \(String(format: "%2d", level))  r≈\(Int(r))m  debounce \(deb)ms  maxRetry \(maxU)  spurIter≤\(spur)  suggest \(String(format: "%.3f", suggestMs))ms  geom \(String(format: "%.3f", geomMs))ms"
            )
        }

        let report = "Route gen LOCAL timing (median-ish over \(reps) iters, no network):\n" + lines.joined(separator: "\n")
        print("\n" + report + "\n")
        XCTAssertEqual(lines.count, levels.count)
    }
}
