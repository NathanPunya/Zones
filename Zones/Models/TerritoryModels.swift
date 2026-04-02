import Foundation
import CoreLocation

struct GeoPointDTO: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ZoneRecord: Identifiable, Codable, Hashable {
    var id: String
    var ownerId: String
    var ownerDisplayName: String
    var polygon: [GeoPointDTO]
    var areaSquareMeters: Double
    var claimedAt: Date
    var difficulty: Double

    var coordinateCentroid: CLLocationCoordinate2D {
        guard !polygon.isEmpty else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        let lat = polygon.map(\.latitude).reduce(0, +) / Double(polygon.count)
        let lon = polygon.map(\.longitude).reduce(0, +) / Double(polygon.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct LeaderboardEntry: Identifiable, Codable, Hashable {
    var id: String { userId }
    var userId: String
    var displayName: String
    var zonesCaptured: Int
    var totalDistanceMeters: Double
    var weeklyScore: Int
    var streakDays: Int
    var updatedAt: Date
}
