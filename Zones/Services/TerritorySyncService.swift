import Combine
import CoreLocation
import Foundation
import FirebaseCore
import FirebaseFirestore

protocol TerritorySyncing: AnyObject {
    var zonesPublisher: AnyPublisher<[ZoneRecord], Never> { get }
    var leaderboardPublisher: AnyPublisher<[LeaderboardEntry], Never> { get }

    func start()
    func claimZone(polygon: [CLLocationCoordinate2D], area: Double, difficulty: Double) async throws
    func updateUserStats(distanceDelta: Double, zonesDelta: Int, weeklyScoreDelta: Int) async throws
}

final class MemoryTerritorySyncService: TerritorySyncing {
    private let subjectZones = CurrentValueSubject<[ZoneRecord], Never>([])
    private let subjectBoard = CurrentValueSubject<[LeaderboardEntry], Never>([])
    private var timer: Timer?

    var zonesPublisher: AnyPublisher<[ZoneRecord], Never> { subjectZones.eraseToAnyPublisher() }
    var leaderboardPublisher: AnyPublisher<[LeaderboardEntry], Never> { subjectBoard.eraseToAnyPublisher() }

    func start() {
        seedIfNeeded()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.pushDemoRipple()
        }
    }

    private func seedIfNeeded() {
        guard subjectBoard.value.isEmpty else { return }
        let uid = UserIdentity.userId
        let demo = LeaderboardEntry(
            userId: uid,
            displayName: UserIdentity.displayName,
            zonesCaptured: 0,
            totalDistanceMeters: 0,
            weeklyScore: 0,
            streakDays: 1,
            updatedAt: Date()
        )
        subjectBoard.send([demo])
    }

    private func pushDemoRipple() {
        // Keeps Combine pipelines warm in demo mode (simulates live leaderboard churn).
        var board = subjectBoard.value
        guard !board.isEmpty else { return }
        for i in board.indices {
            board[i].weeklyScore += Int.random(in: 0...2)
        }
        board.sort { $0.weeklyScore > $1.weeklyScore }
        subjectBoard.send(board)
    }

    func claimZone(polygon: [CLLocationCoordinate2D], area: Double, difficulty: Double) async throws {
        let uid = UserIdentity.userId
        let record = ZoneRecord(
            id: UUID().uuidString,
            ownerId: uid,
            ownerDisplayName: UserIdentity.displayName,
            polygon: polygon.map(GeoPointDTO.init),
            areaSquareMeters: area,
            claimedAt: Date(),
            difficulty: difficulty
        )
        var zones = subjectZones.value
        zones.append(record)
        subjectZones.send(zones)

        var board = subjectBoard.value
        if let idx = board.firstIndex(where: { $0.userId == uid }) {
            board[idx].zonesCaptured += 1
            board[idx].weeklyScore += max(1, Int(area / 100))
            board[idx].totalDistanceMeters += ZoneGeometry.pathLengthMeters(polygon)
            board[idx].updatedAt = Date()
        } else {
            board.append(
                LeaderboardEntry(
                    userId: uid,
                    displayName: UserIdentity.displayName,
                    zonesCaptured: 1,
                    totalDistanceMeters: ZoneGeometry.pathLengthMeters(polygon),
                    weeklyScore: max(1, Int(area / 100)),
                    streakDays: 1,
                    updatedAt: Date()
                )
            )
        }
        board.sort { $0.weeklyScore > $1.weeklyScore }
        subjectBoard.send(board)
    }

    func updateUserStats(distanceDelta: Double, zonesDelta: Int, weeklyScoreDelta: Int) async throws {
        var board = subjectBoard.value
        let uid = UserIdentity.userId
        if let idx = board.firstIndex(where: { $0.userId == uid }) {
            board[idx].totalDistanceMeters += distanceDelta
            board[idx].zonesCaptured += zonesDelta
            board[idx].weeklyScore += weeklyScoreDelta
            board[idx].updatedAt = Date()
        } else {
            board.append(
                LeaderboardEntry(
                    userId: uid,
                    displayName: UserIdentity.displayName,
                    zonesCaptured: zonesDelta,
                    totalDistanceMeters: distanceDelta,
                    weeklyScore: weeklyScoreDelta,
                    streakDays: 1,
                    updatedAt: Date()
                )
            )
        }
        board.sort { $0.weeklyScore > $1.weeklyScore }
        subjectBoard.send(board)
    }
}

final class FirestoreTerritorySyncService: TerritorySyncing {
    /// Lazy so `Firestore` is not touched until after `FirebaseApp.configure()` (SwiftUI can build `MainMapViewModel` very early).
    private lazy var db: Firestore = {
        FirebaseBootstrap.configureIfNeeded()
        return Firestore.firestore()
    }()
    private let subjectZones = CurrentValueSubject<[ZoneRecord], Never>([])
    private let subjectBoard = CurrentValueSubject<[LeaderboardEntry], Never>([])
    private var zoneListener: ListenerRegistration?
    private var boardListener: ListenerRegistration?

    var zonesPublisher: AnyPublisher<[ZoneRecord], Never> { subjectZones.eraseToAnyPublisher() }
    var leaderboardPublisher: AnyPublisher<[LeaderboardEntry], Never> { subjectBoard.eraseToAnyPublisher() }

    func start() {
        zoneListener?.remove()
        boardListener?.remove()

        zoneListener = db.collection("zones").order(by: "claimedAt", descending: true).limit(to: 200).addSnapshotListener { [weak self] snap, _ in
            guard let docs = snap?.documents else { return }
            let parsed: [ZoneRecord] = docs.compactMap { self?.parseZone(id: $0.documentID, data: $0.data()) }
            self?.subjectZones.send(parsed)
        }

        boardListener = db.collection("leaderboard").order(by: "weeklyScore", descending: true).limit(to: 50).addSnapshotListener { [weak self] snap, _ in
            guard let docs = snap?.documents else { return }
            let parsed: [LeaderboardEntry] = docs.compactMap { self?.parseLeader(id: $0.documentID, data: $0.data()) }
            self?.subjectBoard.send(parsed)
        }
    }

    func claimZone(polygon: [CLLocationCoordinate2D], area: Double, difficulty: Double) async throws {
        let uid = UserIdentity.userId
        let name = UserIdentity.displayName
        let zoneRef = db.collection("zones").document()
        let poly: [[String: Double]] = polygon.map { [
            "lat": $0.latitude,
            "lon": $0.longitude
        ] }
        try await zoneRef.setData([
            "ownerId": uid,
            "ownerDisplayName": name,
            "polygon": poly,
            "areaSquareMeters": area,
            "claimedAt": FieldValue.serverTimestamp(),
            "difficulty": difficulty
        ])

        let userRef = db.collection("leaderboard").document(uid)
        let snap = try await userRef.getDocument()
        let prevZones = (snap.data()?["zonesCaptured"] as? Int) ?? 0
        let prevDist = (snap.data()?["totalDistanceMeters"] as? Double) ?? 0
        let prevScore = (snap.data()?["weeklyScore"] as? Int) ?? 0
        let prevStreak = (snap.data()?["streakDays"] as? Int) ?? 0
        try await userRef.setData([
            "userId": uid,
            "displayName": name,
            "zonesCaptured": prevZones + 1,
            "totalDistanceMeters": prevDist + ZoneGeometry.pathLengthMeters(polygon),
            "weeklyScore": prevScore + max(1, Int(area / 100)),
            "streakDays": max(prevStreak, 1),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func updateUserStats(distanceDelta: Double, zonesDelta: Int, weeklyScoreDelta: Int) async throws {
        let uid = UserIdentity.userId
        let userRef = db.collection("leaderboard").document(uid)
        let snap = try await userRef.getDocument()
        let z = (snap.data()?["zonesCaptured"] as? Int) ?? 0
        let d = (snap.data()?["totalDistanceMeters"] as? Double) ?? 0
        let s = (snap.data()?["weeklyScore"] as? Int) ?? 0
        try await userRef.setData([
            "userId": uid,
            "displayName": UserIdentity.displayName,
            "zonesCaptured": z + zonesDelta,
            "totalDistanceMeters": d + distanceDelta,
            "weeklyScore": s + weeklyScoreDelta,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    private func parseZone(id: String, data: [String: Any]) -> ZoneRecord? {
        guard let ownerId = data["ownerId"] as? String,
              let name = data["ownerDisplayName"] as? String,
              let poly = data["polygon"] as? [[String: Any]],
              let area = data["areaSquareMeters"] as? Double else { return nil }
        let coords: [GeoPointDTO] = poly.compactMap { row in
            guard let lat = row["lat"] as? Double, let lon = row["lon"] as? Double else { return nil }
            return GeoPointDTO(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        let claimed: Date = (data["claimedAt"] as? Timestamp)?.dateValue() ?? Date()
        let diff = (data["difficulty"] as? Double) ?? 1
        return ZoneRecord(id: id, ownerId: ownerId, ownerDisplayName: name, polygon: coords, areaSquareMeters: area, claimedAt: claimed, difficulty: diff)
    }

    private func parseLeader(id: String, data: [String: Any]) -> LeaderboardEntry? {
        let userId = (data["userId"] as? String) ?? id
        guard let name = data["displayName"] as? String else { return nil }
        let zones = (data["zonesCaptured"] as? Int) ?? 0
        let dist = (data["totalDistanceMeters"] as? Double) ?? 0
        let score = (data["weeklyScore"] as? Int) ?? 0
        let streak = (data["streakDays"] as? Int) ?? 0
        let updated = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        return LeaderboardEntry(userId: userId, displayName: name, zonesCaptured: zones, totalDistanceMeters: dist, weeklyScore: score, streakDays: streak, updatedAt: updated)
    }
}

enum TerritoryServiceFactory {
    static func makeDefault() -> TerritorySyncing {
        if AppConfiguration.hasFirebasePlist, FirebaseApp.app() != nil {
            return FirestoreTerritorySyncService()
        }
        return MemoryTerritorySyncService()
    }
}
