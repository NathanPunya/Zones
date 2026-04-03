import CoreLocation
import Foundation
import GoogleMaps

/// Snaps a candidate loop to walkable paths using the Google Directions API (same API key as Maps SDK; enable “Directions API” in Google Cloud).
enum GoogleDirectionsService {
    enum DirectionsError: Error {
        case invalidResponse
        case apiStatus(String, String?)
        case noPath
        case invalidAnchors
    }

    /// Short hint for UI when street routing fails (Maps SDK can work while REST Directions is denied).
    static func userFacingHint(for error: Error) -> String {
        guard let err = error as? DirectionsError else {
            return error.localizedDescription
        }
        switch err {
        case .apiStatus(let status, let message):
            let tail: String = {
                guard let m = message, !m.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
                return " (\(m))"
            }()
            switch status {
            case "REQUEST_DENIED":
                return "Request denied — enable Directions API and billing for this Google Cloud project; iOS key restrictions do not apply the same way to REST Directions as to the Maps SDK.\(tail)"
            case "ZERO_RESULTS":
                return "No walking route for this shape — try moving the map, lowering route size, or switching Roads only / Roads & hikes.\(tail)"
            case "INVALID_REQUEST", "NOT_FOUND":
                return "Directions could not build this request (\(status)).\(tail)"
            case "OVER_QUERY_LIMIT", "RESOURCE_EXCEEDED":
                return "Directions quota exceeded. Try again later.\(tail)"
            case "DECODE_ERROR":
                return "Directions returned an unexpected payload (proxy/HTML or wrong endpoint).\(tail)"
            default:
                return "Directions: \(status).\(tail)"
            }
        case .invalidResponse:
            return "Invalid response from Directions."
        case .noPath:
            return "No path in Directions response."
        case .invalidAnchors:
            return "Invalid route anchors."
        }
    }

    /// Cold-start Directions calls can hit transient path/QUIC noise; wait for connectivity and retry URL errors.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    private struct DirectionsResponse: Decodable {
        let routes: [Route]
        let status: String
        let error_message: String?
    }

    private struct Route: Decodable {
        let overview_polyline: Polyline
    }

    private struct Polyline: Decodable {
        let points: String
    }

    /// Closed walking loop: starts and ends at `userLocation`, visiting `loopWaypoints` in an order optimized by Google.
    /// Tries waypoint optimization first; on some failures retries with fixed circular order (often succeeds for `walking` when optimization returns `ZERO_RESULTS`).
    static func fetchWalkingLoop(
        userLocation: CLLocationCoordinate2D,
        loopWaypoints: [CLLocationCoordinate2D],
        surfacePreference: RouteSurfacePreference
    ) async throws -> [CLLocationCoordinate2D] {
        let key = AppConfiguration.googleMapsAPIKey
        guard AppConfiguration.hasGoogleMapsKey, !key.isEmpty else {
            throw DirectionsError.apiStatus("MISSING_KEY", "Add a valid GMSApiKey and enable Directions API.")
        }
        guard loopWaypoints.count >= 2 else { throw DirectionsError.invalidAnchors }
        _ = surfacePreference

        do {
            return try await fetchWalkingLoopOnce(
                key: key,
                userLocation: userLocation,
                loopWaypoints: loopWaypoints,
                optimizeWaypoints: true
            )
        } catch {
            guard shouldRetryWalkingLoopWithFixedWaypointOrder(error) else { throw error }
            return try await fetchWalkingLoopOnce(
                key: key,
                userLocation: userLocation,
                loopWaypoints: loopWaypoints,
                optimizeWaypoints: false
            )
        }
    }

    private static func shouldRetryWalkingLoopWithFixedWaypointOrder(_ error: Error) -> Bool {
        guard let err = error as? DirectionsError else { return false }
        guard case .apiStatus(let status, _) = err else { return false }
        switch status {
        case "REQUEST_DENIED", "OVER_QUERY_LIMIT", "RESOURCE_EXCEEDED", "MAX_WAYPOINTS_EXCEEDED", "MISSING_KEY", "DECODE_ERROR":
            return false
        default:
            return true
        }
    }

    private static func fetchWalkingLoopOnce(
        key: String,
        userLocation: CLLocationCoordinate2D,
        loopWaypoints: [CLLocationCoordinate2D],
        optimizeWaypoints: Bool
    ) async throws -> [CLLocationCoordinate2D] {
        let origin = userLocation
        let destination = userLocation
        let coords = loopWaypoints.map(coordinateString).joined(separator: "|")
        let waypointParam = optimizeWaypoints ? ("optimize:true|" + coords) : coords

        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/directions/json")!
        components.queryItems = [
            URLQueryItem(name: "origin", value: coordinateString(origin)),
            URLQueryItem(name: "destination", value: coordinateString(destination)),
            URLQueryItem(name: "waypoints", value: waypointParam),
            URLQueryItem(name: "mode", value: "walking"),
            URLQueryItem(name: "key", value: key)
        ]

        guard let url = components.url else { throw DirectionsError.invalidResponse }

        let (data, response) = try await dataFromDirectionsAPI(url: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DirectionsError.invalidResponse
        }

        let decoded: DirectionsResponse
        do {
            decoded = try JSONDecoder().decode(DirectionsResponse.self, from: data)
        } catch {
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(280)) } ?? ""
            throw DirectionsError.apiStatus("DECODE_ERROR", snippet.isEmpty ? nil : snippet)
        }
        guard decoded.status == "OK", let route = decoded.routes.first else {
            throw DirectionsError.apiStatus(decoded.status, decoded.error_message)
        }

        let path = decodeOverviewPolyline(route.overview_polyline.points)
        guard path.count >= 2 else { throw DirectionsError.noPath }
        return path
    }

    /// Single walking leg between two points (used to replace redundant out-and-back spurs on a larger loop).
    static func fetchWalkingSegment(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async throws -> [CLLocationCoordinate2D] {
        let key = AppConfiguration.googleMapsAPIKey
        guard AppConfiguration.hasGoogleMapsKey, !key.isEmpty else {
            throw DirectionsError.apiStatus("MISSING_KEY", nil)
        }

        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/directions/json")!
        components.queryItems = [
            URLQueryItem(name: "origin", value: coordinateString(origin)),
            URLQueryItem(name: "destination", value: coordinateString(destination)),
            URLQueryItem(name: "mode", value: "walking"),
            URLQueryItem(name: "key", value: key)
        ]

        guard let url = components.url else { throw DirectionsError.invalidResponse }

        let (data, response) = try await dataFromDirectionsAPI(url: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DirectionsError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(DirectionsResponse.self, from: data)
        guard decoded.status == "OK", let route = decoded.routes.first else {
            throw DirectionsError.apiStatus(decoded.status, decoded.error_message)
        }

        let path = decodeOverviewPolyline(route.overview_polyline.points)
        guard path.count >= 2 else { throw DirectionsError.noPath }
        return path
    }

    private static func dataFromDirectionsAPI(url: URL, attempt: Int = 0) async throws -> (Data, URLResponse) {
        let maxAttempts = 3
        do {
            return try await session.data(from: url)
        } catch {
            guard attempt + 1 < maxAttempts, shouldRetryTransientURLError(error) else { throw error }
            let delayMs = 250 * (attempt + 1)
            try await Task.sleep(for: .milliseconds(delayMs))
            return try await dataFromDirectionsAPI(url: url, attempt: attempt + 1)
        }
    }

    private static func shouldRetryTransientURLError(_ error: Error) -> Bool {
        let code = (error as? URLError)?.code
        switch code {
        case .timedOut,
             .networkConnectionLost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .cannotFindHost,
             .internationalRoamingOff,
             .dataNotAllowed,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    private static func coordinateString(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.7f,%.7f", c.latitude, c.longitude)
    }

    private static func decodeOverviewPolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        guard let path = GMSPath(fromEncodedPath: encoded) else { return [] }
        let n = Int(path.count())
        return (0..<n).map { path.coordinate(at: UInt($0)) }
    }
}
