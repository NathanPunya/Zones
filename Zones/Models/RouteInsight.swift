import Foundation

/// Structured metadata for the suggested loop card (replaces a single long status string).
struct RouteInsight: Equatable {
    var level: Double
    var tierLabel: String
    /// Rough geometric scale of the loop (not the same as path length along streets).
    var targetRadiusMeters: Int
    var score: Double
    /// Internal ranking metric (area/compactness); shown as "Challenge" to avoid confusion with slider level.
    var challengeMetric: Double

    enum PathKind: Equatable {
        case streetSnapped
        case circlePreview
    }

    var pathKind: PathKind
    /// Enclosed area inside the suggested loop (shoelace on the path as a polygon).
    var enclosedAreaSquareMeters: Double
}
