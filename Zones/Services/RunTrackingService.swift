import Combine
import CoreLocation
import Foundation

@MainActor
final class RunTrackingService: NSObject, ObservableObject {
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentLocation: CLLocationCoordinate2D?
    @Published private(set) var runPoints: [CLLocationCoordinate2D] = []
    @Published private(set) var isRecording = false
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var loopClosed = false
    @Published private(set) var enclosedAreaSquareMeters: Double?

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 5
        authorization = manager.authorizationStatus
        startLocationUpdatesIfAuthorized()
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Keeps GPS warm for the map and route suggestions even when you are not recording a run.
    private func startLocationUpdatesIfAuthorized() {
        switch authorization {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func startRecording() {
        runPoints.removeAll()
        distanceMeters = 0
        loopClosed = false
        enclosedAreaSquareMeters = nil
        lastLocation = nil
        isRecording = true
        startLocationUpdatesIfAuthorized()
    }

    func stopRecording() {
        isRecording = false
        // Keep location updates for map + suggested route; recording path is no longer appended.
    }

    private func appendCoordinate(_ coordinate: CLLocationCoordinate2D) {
        runPoints.append(coordinate)
        if runPoints.count >= 2, let last = lastLocation {
            let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            distanceMeters += last.distance(from: loc)
        }
        lastLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        let closed = ZoneGeometry.isClosedLoop(points: runPoints)
        loopClosed = closed
        if closed {
            enclosedAreaSquareMeters = ZoneGeometry.areaSquareMeters(polygon: runPoints)
        } else {
            enclosedAreaSquareMeters = nil
        }
    }
}

extension RunTrackingService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorization = manager.authorizationStatus
            self.startLocationUpdatesIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            let coord = loc.coordinate
            self.currentLocation = coord
            if self.isRecording {
                self.appendCoordinate(coord)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("Location error: \(error.localizedDescription)")
        #endif
    }
}
