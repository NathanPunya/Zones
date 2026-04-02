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

        let origin = userLocation
        let destination = userLocation

        // Reorder intermediate stops to minimize total walking distance (fewer redundant blocks in grid cities).
        let waypointParam = "optimize:true|" + loopWaypoints.map(coordinateString).joined(separator: "|")

        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/directions/json")!
        components.queryItems = [
            URLQueryItem(name: "origin", value: coordinateString(origin)),
            URLQueryItem(name: "destination", value: coordinateString(destination)),
            URLQueryItem(name: "waypoints", value: waypointParam),
            URLQueryItem(name: "mode", value: "walking"),
            URLQueryItem(name: "key", value: key)
        ]
        // Waypoint layout comes from `surfacePreference` in `RouteSuggestionEngine`; request stays `walking` for both.
        _ = surfacePreference

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
