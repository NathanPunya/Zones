import Combine
import CoreLocation
import Foundation

@MainActor
final class MainMapViewModel: ObservableObject {
    @Published var cameraTarget: CLLocationCoordinate2D?
    @Published var zones: [ZoneRecord] = []
    @Published var leaderboard: [LeaderboardEntry] = []
    @Published var suggestedLoops: [[CLLocationCoordinate2D]] = []
    @Published var suggestedRouteDistanceMeters: Double = 0
    /// Default ≈ former level 5 on the old 1…50 scale → display **4** on 1…25 (see `RouteSuggestionEngine`).
    @Published var desiredDifficulty: Double = 4
    /// When false, the green AI route is hidden on the map (data stays cached).
    @Published var showAIRoute: Bool = true

    /// Card content for the current suggestion (target radius vs street distance are both explained in the UI).
    @Published var routeInsight: RouteInsight?
    @Published var isRefreshingSuggestedRoute = false
    /// Short transient messages (errors, claim success).
    @Published var bannerMessage: String?

    private let sync: TerritorySyncing
    private let logStore: AppDiagnosticsLogStore
    private let routeEngine = RouteSuggestionEngine()
    private var cancellables = Set<AnyCancellable>()
    private var routeFetchTask: Task<Void, Never>?
    /// Extra rotation for waypoint placement when the last polyline would repeat (any refresh).
    private var routeOrientationBiasRadians: Double = 0
    /// Last shown AI polyline fingerprint; new routes must differ (slider changes, new level, or “New route”).
    private var lastDisplayedRouteSignature: String?
    /// Incremented on each `refreshSuggestions` with a valid center so only the latest in-flight fetch may finish UI/loading.
    private var refreshEpoch: UInt64 = 0

    init(sync: TerritorySyncing, logStore: AppDiagnosticsLogStore) {
        self.sync = sync
        self.logStore = logStore
    }

    deinit {
        routeFetchTask?.cancel()
    }

    func start() {
        sync.start()
        sync.zonesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] zones in
                self?.zones = zones
            }
            .store(in: &cancellables)

        sync.leaderboardPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] board in
                self?.leaderboard = board
            }
            .store(in: &cancellables)
    }

    /// - Parameter rotateForNewRoute: If true, nudges anchor orientation so Directions can return a different loop without changing level.
    /// - Parameter showsProgress: When false (e.g. GPS/auth-driven refresh), the route updates silently without loading UI.
    func refreshSuggestions(
        center: CLLocationCoordinate2D?,
        recentDistances: [Double],
        surfacePreference: RouteSurfacePreference,
        rotateForNewRoute: Bool = false,
        showsProgress: Bool = true
    ) {
        routeFetchTask?.cancel()
        guard let center else {
            if showsProgress {
                isRefreshingSuggestedRoute = false
            }
            return
        }

        refreshEpoch += 1
        let epoch = refreshEpoch
        let affectsLoadingUI = showsProgress

        if !rotateForNewRoute {
            routeOrientationBiasRadians = 0
        }

        if affectsLoadingUI {
            isRefreshingSuggestedRoute = true
            bannerMessage = nil
        } else {
            isRefreshingSuggestedRoute = false
        }

        routeFetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(480))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard epoch == self.refreshEpoch else { return }

            let maxUniquenessAttempts = 16
            var uniquenessAttempt = 0

            while true {
                if uniquenessAttempt == 0 && rotateForNewRoute {
                    self.routeOrientationBiasRadians += (Double.pi * 2) / 7
                } else if uniquenessAttempt > 0 {
                    self.routeOrientationBiasRadians += (Double.pi * 2) / 7
                }

                guard let built = await self.computeSuggestedLoop(
                    center: center,
                    recentDistances: recentDistances,
                    surfacePreference: surfacePreference
                ) else {
                    guard epoch == self.refreshEpoch else { return }
                    self.suggestedLoops = []
                    self.suggestedRouteDistanceMeters = 0
                    self.routeInsight = nil
                    if affectsLoadingUI {
                        self.isRefreshingSuggestedRoute = false
                    }
                    if affectsLoadingUI {
                        self.bannerMessage = "No suggested loop here — try moving the map or adjusting the slider."
                    }
                    return
                }
                guard epoch == self.refreshEpoch else { return }

                let (loop, best, pathKind) = built
                let sig = ZoneGeometry.polylineSignature(loop)

                if let previous = self.lastDisplayedRouteSignature,
                   sig == previous,
                   uniquenessAttempt < maxUniquenessAttempts - 1 {
                    uniquenessAttempt += 1
                    if Task.isCancelled {
                        if epoch == self.refreshEpoch, affectsLoadingUI {
                            self.isRefreshingSuggestedRoute = false
                        }
                        return
                    }
                    continue
                }

                if let previous = self.lastDisplayedRouteSignature, sig == previous, affectsLoadingUI {
                    self.bannerMessage = "Couldn’t find a different route — try moving the map or changing level."
                }

                guard !Task.isCancelled else {
                    if epoch == self.refreshEpoch, affectsLoadingUI {
                        self.isRefreshingSuggestedRoute = false
                    }
                    return
                }
                guard epoch == self.refreshEpoch else { return }

                self.lastDisplayedRouteSignature = sig
                self.suggestedLoops = [loop]
                self.suggestedRouteDistanceMeters = ZoneGeometry.pathLengthMeters(loop)
                let areaM2 = ZoneGeometry.enclosedAreaAlongRoute(loop)
                self.routeInsight = RouteInsight(
                    level: best.sliderLevel,
                    tierLabel: best.tierLabel,
                    targetRadiusMeters: Int(best.targetRadiusMeters.rounded()),
                    score: best.score,
                    challengeMetric: best.difficulty,
                    pathKind: pathKind,
                    enclosedAreaSquareMeters: areaM2
                )
                if affectsLoadingUI {
                    self.isRefreshingSuggestedRoute = false
                }
                return
            }
        }
    }

    /// Builds one candidate loop using current `routeOrientationBiasRadians`.
    private func computeSuggestedLoop(
        center: CLLocationCoordinate2D,
        recentDistances: [Double],
        surfacePreference: RouteSurfacePreference
    ) async -> ([CLLocationCoordinate2D], RouteSuggestionEngine.Suggestion, RouteInsight.PathKind)? {
        let suggestions = routeEngine.suggest(
            center: center,
            existingZones: zones,
            recentRunDistances: recentDistances,
            desiredDifficulty: desiredDifficulty,
            surfacePreference: surfacePreference,
            extraAngleRadians: routeOrientationBiasRadians
        )

        guard var best = suggestions.first else { return nil }

        let loop: [CLLocationCoordinate2D]
        var pathKind = RouteInsight.PathKind.circlePreview

        if AppConfiguration.hasGoogleMapsKey {
            do {
                var path = try await GoogleDirectionsService.fetchWalkingLoop(
                    userLocation: best.userLocation,
                    loopWaypoints: best.loopWaypoints,
                    surfacePreference: surfacePreference
                )
                pathKind = .streetSnapped
                if RoutePathRefinement.corridorReuseScore(path: path) > 0.28 {
                    for extra in [Double.pi / 4, -Double.pi / 3, Double.pi / 2] {
                        guard let alt = routeEngine.suggest(
                            center: center,
                            existingZones: zones,
                            recentRunDistances: recentDistances,
                            desiredDifficulty: desiredDifficulty,
                            surfacePreference: surfacePreference,
                            extraAngleRadians: routeOrientationBiasRadians + extra
                        ).first else { continue }
                        do {
                            let candidate = try await GoogleDirectionsService.fetchWalkingLoop(
                                userLocation: alt.userLocation,
                                loopWaypoints: alt.loopWaypoints,
                                surfacePreference: surfacePreference
                            )
                            if RoutePathRefinement.corridorReuseScore(path: candidate)
                                < RoutePathRefinement.corridorReuseScore(path: path) {
                                path = candidate
                                best = alt
                            }
                            if RoutePathRefinement.corridorReuseScore(path: path) < 0.16 { break }
                        } catch {
                            continue
                        }
                    }
                }
                path = await RoutePathRefinement.refinedByShorteningSpurs(path)
                loop = path
            } catch {
                pathKind = .circlePreview
                loop = best.fallbackDense
                logStore.logGoogleDirectionsFallback(GoogleDirectionsService.userFacingHint(for: error))
            }
        } else {
            loop = best.fallbackDense
        }

        return (loop, best, pathKind)
    }

    func claimLoop(points: [CLLocationCoordinate2D], area: Double) async {
        guard points.count >= 4 else { return }
        let difficulty = max(0.5, area / 5000)
        do {
            try await sync.claimZone(polygon: points, area: area, difficulty: difficulty)
            bannerMessage = "Zone claimed and synced."
        } catch {
            bannerMessage = "Could not sync zone: \(error.localizedDescription)"
        }
    }
}
