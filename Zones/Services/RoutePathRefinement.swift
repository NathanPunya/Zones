import CoreLocation
import Foundation

/// Heuristics to reduce redundant running (same corridor twice) on Google walking polylines.
enum RoutePathRefinement {
    /// 0 = little reuse, 1 = heavy reuse of the same corridors.
    static func corridorReuseScore(path: [CLLocationCoordinate2D]) -> Double {
        guard path.count > 24 else { return 0 }
        let cellDeg = 0.00022 // ~25 m
        var lastIndexForCell: [String: Int] = [:]
        var revisit = 0
        var samples = 0
        let strideBy = max(1, path.count / 100)
        for i in Swift.stride(from: 0, to: path.count, by: strideBy) {
            let p = path[i]
            let key = "\(Int(p.latitude / cellDeg))_\(Int(p.longitude / cellDeg))"
            samples += 1
            if let prev = lastIndexForCell[key], i - prev > 12 {
                revisit += 1
            }
            lastIndexForCell[key] = i
        }
        guard samples > 0 else { return 0 }
        return Double(revisit) / Double(samples)
    }

    /// Replaces **out-and-back** segments (long path, endpoints close) with a fresh walking leg from Directions.
    /// Safe: on failure or no improvement, returns the input unchanged.
    static func refinedByShorteningSpurs(_ path: [CLLocationCoordinate2D]) async -> [CLLocationCoordinate2D] {
        guard AppConfiguration.hasGoogleMapsKey, path.count > 24 else { return path }

        var current = path

        for _ in 0..<8 {
            guard let range = findLargestSpurRange(in: current) else { break }
            let (i, j) = range
            guard i >= 0, j < current.count, j - i > 8 else { break }

            let lenBefore = ZoneGeometry.pathLengthMeters(current)

            do {
                let bridge = try await GoogleDirectionsService.fetchWalkingSegment(
                    from: current[i],
                    to: current[j]
                )
                guard bridge.count >= 2 else { break }

                let merged = mergeReplacingSpur(current, i: i, j: j, bridge: bridge)
                guard merged.count >= 12 else { break }

                let lenAfter = ZoneGeometry.pathLengthMeters(merged)
                // Accept small savings: short block out-and-backs may only shave a few tens of meters.
                if lenAfter >= lenBefore * 0.995 { break }

                current = dedupeNearbyPoints(merged, minSeparationMeters: 3.5)
            } catch {
                break
            }
        }

        return current
    }

    /// Finds (i, j) where the subpath is much longer than the straight line between endpoints (dead-end / down-and-back on same corridor).
    private static func findLargestSpurRange(in path: [CLLocationCoordinate2D]) -> (Int, Int)? {
        guard path.count > 22 else { return nil }
        let n = path.count
        var best: (Int, Int)?
        var bestWaste: Double = 0

        for i in 0..<(n - 12) {
            var j = i + 10
            let jMax = min(i + 520, n - 1)
            while j <= jMax {
                let net = meters(path[i], path[j])
                let slice = Array(path[i ... j])
                let plen = ZoneGeometry.pathLengthMeters(slice)
                let span = j - i

                // Endpoints near each other but path along the corridor is long = out-and-back.
                // Thresholds tuned for short city blocks (see overly long “spurs” on grid routes).
                let isSpur = net < 95
                    && plen > 42
                    && plen > net * 1.62
                if isSpur {
                    if span >= n / 2 { j += 2; continue }
                    if i < 10 && j > n - 12 { j += 2; continue }
                    if span < 8 { j += 2; continue }

                    let waste = plen - net
                    if waste > bestWaste {
                        bestWaste = waste
                        best = (i, j)
                    }
                }
                j += 1
            }
        }
        return best
    }

    private static func mergeReplacingSpur(
        _ path: [CLLocationCoordinate2D],
        i: Int,
        j: Int,
        bridge: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        guard i >= 0, j < path.count, i < j else { return path }

        var out: [CLLocationCoordinate2D] = []
        if i > 0 {
            out.append(contentsOf: path[0 ..< i])
        }

        var mid = bridge
        if let f = mid.first, meters(f, path[i]) < 6 {
            mid = Array(mid.dropFirst())
        }
        out.append(path[i])
        out.append(contentsOf: mid)

        if j + 1 < path.count {
            out.append(contentsOf: path[j + 1 ..< path.count])
        }
        return out
    }

    private static func dedupeNearbyPoints(_ path: [CLLocationCoordinate2D], minSeparationMeters: Double) -> [CLLocationCoordinate2D] {
        guard var previous = path.first else { return path }
        var out: [CLLocationCoordinate2D] = [previous]
        for point in path.dropFirst() {
            if meters(previous, point) >= minSeparationMeters {
                out.append(point)
                previous = point
            }
        }
        return out
    }

    private static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
