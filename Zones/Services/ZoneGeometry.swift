import CoreLocation
import Foundation

enum ZoneGeometry {
    /// Shoelace formula — polygon assumed simple (non self-intersecting).
    static func areaSquareMeters(polygon: [CLLocationCoordinate2D]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        let p = closedPolygon(polygon)
        var sum: Double = 0
        for i in 0..<(p.count - 1) {
            let a = p[i]
            let b = p[i + 1]
            sum += (a.longitude * b.latitude - b.longitude * a.latitude)
        }
        let areaDeg = abs(sum) * 0.5
        // Rough conversion using latitude for scale (adequate for local city-scale loops).
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(p[0].latitude * .pi / 180)
        return areaDeg * metersPerDegLat * metersPerDegLon
    }

    /// Area inside the loop described by the route polyline (last point is connected to first if needed). For complex self‑crossing paths this is an approximation.
    static func enclosedAreaAlongRoute(_ points: [CLLocationCoordinate2D]) -> Double {
        areaSquareMeters(polygon: points)
    }

    static func closedPolygon(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard let first = points.first, let last = points.last else { return points }
        if first.latitude != last.latitude || first.longitude != last.longitude {
            return points + [first]
        }
        return points
    }

    static func isClosedLoop(points: [CLLocationCoordinate2D], thresholdMeters: Double = 35) -> Bool {
        guard points.count >= 4 else { return false }
        guard let first = points.first else { return false }
        let last = points.last!
        let a = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let b = CLLocation(latitude: last.latitude, longitude: last.longitude)
        return a.distance(from: b) <= thresholdMeters
    }

    static func pathLengthMeters(_ points: [CLLocationCoordinate2D]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<points.count {
            let a = CLLocation(latitude: points[i - 1].latitude, longitude: points[i - 1].longitude)
            let b = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            total += a.distance(from: b)
        }
        return total
    }

    static func boundingBox(for coordinates: [CLLocationCoordinate2D]) -> (min: CLLocationCoordinate2D, max: CLLocationCoordinate2D)? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        return (CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon))
    }

    /// Fingerprint for comparing two walking polylines (count, length, sampled coordinates).
    static func polylineSignature(_ path: [CLLocationCoordinate2D]) -> String {
        guard let first = path.first, let last = path.last else { return "" }
        let n = path.count
        let len = pathLengthMeters(path)
        let i1 = n > 1 ? n / 4 : 0
        let i2 = n > 2 ? n / 2 : 0
        let i3 = n > 3 ? (3 * n) / 4 : n - 1
        func s(_ p: CLLocationCoordinate2D) -> String {
            String(format: "%.5f,%.5f", p.latitude, p.longitude)
        }
        return "\(n)_\(Int(len.rounded()))_\(s(first))_\(s(path[i1]))_\(s(path[i2]))_\(s(path[i3]))_\(s(last))"
    }
}
