import SwiftUI
import CoreLocation
import UIKit

/// Retained generator + `prepare()` avoids first-tick lag from creating `UIImpactFeedbackGenerator` on every level step.
private enum RouteLevelTickHaptics {
    private static let generator = UIImpactFeedbackGenerator(style: .rigid)

    static func warmUp() {
        generator.prepare()
    }

    static func play(intensity: CGFloat = 0.6) {
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }
}

struct ContentView: View {
    @ObservedObject var runTracker: RunTrackingService
    @ObservedObject var motion: CoreMotionService
    @ObservedObject var health: HealthKitService
    @ObservedObject var streaks: StreakService
    @ObservedObject var notifications: TerritoryNotificationService

    @StateObject private var mapModel: MainMapViewModel
    /// One-time center on first GPS fix; ongoing location updates must not keep resetting the camera.
    @State private var hasAppliedInitialMapCenter = false
    /// Avoids cancelling an in-flight Directions fetch on every GPS tweak (first-launch location churn).
    @State private var locationRefreshDebounceTask: Task<Void, Never>?
    /// Continuous thumb position for route level; avoids stepped `Slider` tick haptics fighting at 24↔25 (system 32 Hz limit).
    @State private var routeLevelSliderValue: Double = 4
    /// Last level we played a tick haptic for (only fires when this integer changes).
    @State private var routeSliderLastHapticLevel: Int?
    @AppStorage("measurementUnits") private var measurementUnitsRaw = MeasurementUnits.metric.rawValue
    @AppStorage("routeSurfacePreference") private var routeSurfaceRaw = RouteSurfacePreference.streetsAndSidewalks.rawValue
    @AppStorage("mapDisplayMode") private var mapDisplayModeRaw = MapDisplayMode.standard.rawValue
    @AppStorage("mapTrafficEnabled") private var mapTrafficEnabled = false

    private var measurementUnits: MeasurementUnits {
        MeasurementUnits(rawValue: measurementUnitsRaw) ?? .metric
    }

    private var routeSurfacePreference: RouteSurfacePreference {
        RouteSurfacePreference(rawValue: routeSurfaceRaw) ?? .streetsAndSidewalks
    }

    private var mapDisplayMode: MapDisplayMode {
        MapDisplayMode(rawValue: mapDisplayModeRaw) ?? .standard
    }

    private static let routeGenToggleAnimation = Animation.spring(response: 0.48, dampingFraction: 0.86)

    private static var routeGenSectionTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity.combined(with: .move(edge: .bottom))
        )
    }

    init(
        runTracker: RunTrackingService,
        motion: CoreMotionService,
        health: HealthKitService,
        streaks: StreakService,
        notifications: TerritoryNotificationService
    ) {
        self.runTracker = runTracker
        self.motion = motion
        self.health = health
        self.streaks = streaks
        self.notifications = notifications
        _mapModel = StateObject(wrappedValue: MainMapViewModel(sync: TerritoryServiceFactory.makeDefault()))
    }

    var body: some View {
        TabView {
            NavigationStack {
                VStack(spacing: 0) {
                    mapHeaderBar

                    ZStack(alignment: .bottom) {
                        GoogleMapView(
                            cameraTarget: $mapModel.cameraTarget,
                            mapDisplayMode: mapDisplayMode,
                            trafficEnabled: mapTrafficEnabled,
                            routePoints: runTracker.runPoints,
                            zonePolygons: mapModel.zones,
                            suggestedRoutes: mapModel.showAIRoute ? mapModel.suggestedLoops : []
                        )
                        .ignoresSafeArea(edges: [.bottom, .leading, .trailing])

                        VStack {
                            HStack {
                                Spacer()
                                mapRecenterButton
                            }
                            Spacer()
                        }
                        .padding(.top, 6)
                        .padding(.trailing, 10)

                        VStack(alignment: .leading, spacing: 8) {
                            if !AppConfiguration.hasGoogleMapsKey {
                                Text("Add GOOGLE_MAPS_API_KEY to a .env file at the project root, then build.")
                                    .font(.caption)
                                    .padding(8)
                                    .background(.thinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            if !AppConfiguration.hasFirebasePlist {
                                Text("Demo mode: add GoogleService-Info.plist to sync with Firestore.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            }
                            HStack {
                                Spacer()
                                if motion.isRunningLikely {
                                    Label("Running", systemImage: "figure.run")
                                        .font(.caption)
                                        .padding(8)
                                        .background(.green.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                            Spacer()
                        }
                        .padding()

                        controlPanel
                    }
                }
                .navigationBarHidden(true)
            }
            .tabItem {
                Label("Map", systemImage: "map")
            }

            NavigationStack {
                LeaderboardView(entries: mapModel.leaderboard, currentUserId: UserIdentity.userId)
            }
            .tabItem {
                Label("Leaderboard", systemImage: "trophy.fill")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .environment(\.measurementUnits, measurementUnits)
        .onAppear {
            routeLevelSliderValue = mapModel.desiredDifficulty
            routeSliderLastHapticLevel = Int(mapModel.desiredDifficulty.rounded())
            RouteLevelTickHaptics.warmUp()
            mapModel.start()
            runTracker.requestAuthorization()
            motion.start()
            Task {
                await health.requestAuthorization()
                await notifications.requestPermission()
                notifications.scheduleStreakReminderIfNeeded(streakDays: streaks.currentStreakDays)
            }
        }
        .onChange(of: runTracker.authorization) { _, status in
            guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
            guard mapModel.showAIRoute else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard let c = runTracker.currentLocation else { return }
                let distances = await health.recentRunDistances(days: 14)
                mapModel.refreshSuggestions(
                    center: c,
                    recentDistances: distances,
                    surfacePreference: routeSurfacePreference,
                    showsProgress: false
                )
            }
        }
        .onChange(of: locationFingerprint) { _, _ in
            guard let new = runTracker.currentLocation else { return }
            if !hasAppliedInitialMapCenter {
                mapModel.cameraTarget = new
                hasAppliedInitialMapCenter = true
            }
            guard mapModel.showAIRoute else { return }
            locationRefreshDebounceTask?.cancel()
            locationRefreshDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(1600))
                guard !Task.isCancelled else { return }
                guard mapModel.showAIRoute, let c = runTracker.currentLocation else { return }
                let distances = await health.recentRunDistances(days: 14)
                mapModel.refreshSuggestions(
                    center: c,
                    recentDistances: distances,
                    surfacePreference: routeSurfacePreference,
                    showsProgress: false
                )
            }
        }
        .onChange(of: routeSurfaceRaw) { _, _ in
            guard mapModel.showAIRoute, let c = runTracker.currentLocation else { return }
            Task {
                let distances = await health.recentRunDistances(days: 14)
                mapModel.refreshSuggestions(center: c, recentDistances: distances, surfacePreference: routeSurfacePreference)
            }
        }
        .onChange(of: mapModel.showAIRoute) { _, enabled in
            if enabled {
                RouteLevelTickHaptics.warmUp()
                // Warms HealthKit so the first slider-driven refresh does not pay a cold query on the gesture path.
                Task { _ = await health.recentRunDistances(days: 14) }
            }
            guard enabled, let c = runTracker.currentLocation else { return }
            // Re-showing the route uses cached geometry/insight; only fetch when nothing was generated yet.
            guard mapModel.suggestedLoops.isEmpty, mapModel.routeInsight == nil else { return }
            Task {
                let distances = await health.recentRunDistances(days: 14)
                mapModel.refreshSuggestions(center: c, recentDistances: distances, surfacePreference: routeSurfacePreference)
            }
        }
    }

    private func playRouteLevelTickHaptic() {
        RouteLevelTickHaptics.play()
    }

    private var locationFingerprint: String {
        guard let c = runTracker.currentLocation else { return "" }
        return String(format: "%.5f,%.5f", c.latitude, c.longitude)
    }

    /// Custom header (not `ToolbarItem`) avoids the system bar-button “glass” behind the streak.
    private var mapHeaderBar: some View {
        ZStack {
            HStack(spacing: 0) {
                streakChip
                Spacer(minLength: 12)
                mapRouteToggleButton
            }
            Text("Zones")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(.primary.opacity(0.92))
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var mapRouteToggleButton: some View {
        Button {
            withAnimation(Self.routeGenToggleAnimation) {
                mapModel.showAIRoute.toggle()
            }
        } label: {
            Image(systemName: mapModel.showAIRoute ? "map.fill" : "map")
                .font(.body.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(mapModel.showAIRoute ? Color.orange : Color.primary.opacity(0.72))
        .accessibilityLabel(mapModel.showAIRoute ? "Hide AI route" : "Show AI route")
    }

    /// Replaces the SDK my-location control (fixed bottom-right); same action, top-right of the map.
    private var mapRecenterButton: some View {
        Button {
            guard let c = runTracker.currentLocation else { return }
            mapModel.cameraTarget = c
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.blue)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(runTracker.currentLocation == nil)
        .opacity(runTracker.currentLocation == nil ? 0.4 : 1)
        .accessibilityLabel("Recenter on your location")
    }

    private var streakChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
            Text("\(streaks.currentStreakDays) streak")
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .font(.caption)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill))
        .clipShape(Capsule())
    }

    /// Drives cross-fade between loading row and insight card without tying to `showAIRoute`.
    private var routeGenContentPhase: String {
        if mapModel.routeInsight != nil { return "insight" }
        if mapModel.isRefreshingSuggestedRoute { return "loading" }
        return "empty"
    }

    private var routeGenLoadingPlaceholder: some View {
        HStack(spacing: 10) {
            Image(systemName: "map")
                .font(.body.weight(.medium))
                .foregroundStyle(.orange)
                .frame(width: 22)
            ProgressView()
            Text("Building route…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var controlPanel: some View {
        VStack(spacing: 12) {
            if mapModel.showAIRoute {
                VStack(spacing: 12) {
                    if let insight = mapModel.routeInsight {
                        RouteInsightCard(
                            insight: insight,
                            pathDistanceMeters: mapModel.suggestedRouteDistanceMeters,
                            isLoading: mapModel.isRefreshingSuggestedRoute
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                    } else if mapModel.isRefreshingSuggestedRoute {
                        routeGenLoadingPlaceholder
                            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                    }

                    Button {
                        Task { await scheduleSuggestedRouteRefresh(rotateForNewRoute: true) }
                    } label: {
                        Label("New route", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(mapModel.isRefreshingSuggestedRoute || runTracker.currentLocation == nil)
                    .opacity((mapModel.isRefreshingSuggestedRoute || runTracker.currentLocation == nil) ? 0.45 : 1)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Route size (easier → harder)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Lv \(Int(routeLevelSliderValue.rounded()))")
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                                Text(RouteSuggestionEngine.tierLabel(forSliderLevel: routeLevelSliderValue.rounded()))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                        Slider(
                            value: $routeLevelSliderValue,
                            in: RouteSuggestionEngine.difficultySliderRange
                        ) { editing in
                            if !editing {
                                let r = routeLevelSliderValue.rounded()
                                routeLevelSliderValue = r
                            }
                        }
                        .onChange(of: routeLevelSliderValue) { _, v in
                            let level = Int(v.rounded())
                            if level != routeSliderLastHapticLevel {
                                routeSliderLastHapticLevel = level
                                playRouteLevelTickHaptic()
                            }
                            let r = v.rounded()
                            guard r != mapModel.desiredDifficulty else { return }
                            mapModel.desiredDifficulty = r
                            guard mapModel.showAIRoute, let c = runTracker.currentLocation else { return }
                            Task {
                                let distances = await health.recentRunDistances(days: 14)
                                mapModel.refreshSuggestions(center: c, recentDistances: distances, surfacePreference: routeSurfacePreference)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
                .animation(.easeInOut(duration: 0.28), value: routeGenContentPhase)
                .transition(Self.routeGenSectionTransition)
            }

            if let banner = mapModel.bannerMessage, !banner.isEmpty {
                Text(banner)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 12) {
                Button(action: toggleRun) {
                    Label(runTracker.isRecording ? "Stop" : "Start run", systemImage: runTracker.isRecording ? "stop.fill" : "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(runTracker.isRecording ? .red : .orange)

                Button("Claim zone") {
                    Task { await claimZone() }
                }
                .buttonStyle(.bordered)
                .disabled(!runTracker.loopClosed || runTracker.runPoints.count < 4)
            }
        }
        .animation(Self.routeGenToggleAnimation, value: mapModel.showAIRoute)
        .padding()
        .background(.ultraThinMaterial)
    }

    /// Fetches HealthKit context and refreshes the AI loop. Use `rotateForNewRoute` to get a different path at the same level.
    private func scheduleSuggestedRouteRefresh(rotateForNewRoute: Bool = false, showsProgress: Bool = true) async {
        guard mapModel.showAIRoute, let center = runTracker.currentLocation else { return }
        let distances = await health.recentRunDistances(days: 14)
        mapModel.refreshSuggestions(
            center: center,
            recentDistances: distances,
            surfacePreference: routeSurfacePreference,
            rotateForNewRoute: rotateForNewRoute,
            showsProgress: showsProgress
        )
    }

    private func toggleRun() {
        if runTracker.isRecording {
            runTracker.stopRecording()
            motion.stop()
        } else {
            runTracker.startRecording()
            motion.startPedometer(from: Date())
        }
    }

    private func claimZone() async {
        guard let area = runTracker.enclosedAreaSquareMeters, runTracker.loopClosed else { return }
        await mapModel.claimLoop(points: runTracker.runPoints, area: area)
        streaks.registerActivity()
        notifications.notifyZoneClaimed(area: area)
        notifications.scheduleStreakReminderIfNeeded(streakDays: streaks.currentStreakDays)
        let start = Date().addingTimeInterval(-120)
        await health.saveZoneRun(distanceMeters: runTracker.distanceMeters, start: start, end: Date())
    }
}

#Preview {
    ContentView(
        runTracker: RunTrackingService(),
        motion: CoreMotionService(),
        health: HealthKitService(),
        streaks: StreakService(),
        notifications: TerritoryNotificationService()
    )
    .environment(\.measurementUnits, .metric)
}
