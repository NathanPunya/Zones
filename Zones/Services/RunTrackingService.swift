import Combine
import CoreLocation
import Foundation
import UIKit

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

    private var lastSnapshotSave = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 5
        authorization = manager.authorizationStatus
        restorePersistedSessionIfNeeded()
        startLocationUpdatesIfAuthorized()
        _ = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.persistRecordingSnapshotIfNeeded()
            }
        }
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
        clearRecordingSnapshot()
        runPoints.removeAll()
        distanceMeters = 0
        loopClosed = false
        enclosedAreaSquareMeters = nil
        lastLocation = nil
        lastSnapshotSave = .distantPast
        isRecording = true
        startLocationUpdatesIfAuthorized()
        persistRecordingSnapshotIfNeeded()
    }

    func stopRecording() {
        isRecording = false
        clearRecordingSnapshot()
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

        maybePersistAfterAppend()
    }

    private func maybePersistAfterAppend() {
        guard isRecording else { return }
        let n = runPoints.count
        let now = Date()
        if n <= 1 || n % 4 == 0 || now.timeIntervalSince(lastSnapshotSave) >= 2.0 {
            persistRecordingSnapshotIfNeeded()
            lastSnapshotSave = now
        }
    }

    private func persistRecordingSnapshotIfNeeded() {
        guard isRecording else { return }
        let snapshot = PersistedRunSession(
            active: true,
            distanceMeters: distanceMeters,
            lastLatitude: lastLocation?.coordinate.latitude,
            lastLongitude: lastLocation?.coordinate.longitude,
            points: runPoints.map { [$0.latitude, $0.longitude] }
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistenceKey)
    }

    private func clearRecordingSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
    }

    private func restorePersistedSessionIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
        #endif
        guard let data = UserDefaults.standard.data(forKey: Self.persistenceKey) else { return }
        guard let session = try? JSONDecoder().decode(PersistedRunSession.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
            return
        }
        guard session.active else {
            clearRecordingSnapshot()
            return
        }

        runPoints = session.points.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
        distanceMeters = session.distanceMeters
        if let la = session.lastLatitude, let lo = session.lastLongitude {
            lastLocation = CLLocation(latitude: la, longitude: lo)
        } else if let last = runPoints.last {
            lastLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
        } else {
            lastLocation = nil
        }
        isRecording = true
        let closed = ZoneGeometry.isClosedLoop(points: runPoints)
        loopClosed = closed
        enclosedAreaSquareMeters = closed ? ZoneGeometry.areaSquareMeters(polygon: runPoints) : nil
        lastSnapshotSave = Date()
    }

    private static let persistenceKey = "zones.runTracking.activeSession.v2"
}

// MARK: - Persistence

private struct PersistedRunSession: Codable {
    /// True when the user had tapped Start run and not Stop (survives process death).
    var active: Bool
    var distanceMeters: Double
    var lastLatitude: Double?
    var lastLongitude: Double?
    /// Each entry is `[latitude, longitude]`.
    var points: [[Double]]
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
