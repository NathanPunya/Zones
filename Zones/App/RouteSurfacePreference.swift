import Foundation

/// How AI loop routes are snapped via Google Directions (`walking`). Stored in `UserDefaults`.
enum RouteSurfacePreference: String, CaseIterable, Identifiable {
    /// Tighter loop with fewer intermediate points — tends to follow sidewalks and street grids.
    case streetsAndSidewalks
    /// More intermediate points so the optimizer visits more varied walking paths (parks, trails) where Google maps them.
    case pathsAndTrails

    var id: String { rawValue }

    var title: String {
        switch self {
        case .streetsAndSidewalks: return "Roads only"
        case .pathsAndTrails: return "Roads & hikes"
        }
    }

    /// Number of perimeter waypoints (not including your position). More waypoints → broader exploration.
    var perimeterWaypointCount: Int {
        switch self {
        case .streetsAndSidewalks: return 3
        case .pathsAndTrails: return 5
        }
    }
}

/// Map provider / style (`UserDefaults` key `mapDisplayMode`). Google options use `GMSMapView`; Apple options use MapKit.
enum MapDisplayMode: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case appleMaps
    case appleMapsSatellite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard (Google)"
        case .satellite: return "Satellite (Google)"
        case .appleMaps: return "Standard (Apple)"
        case .appleMapsSatellite: return "Satellite (Apple)"
        }
    }
}
