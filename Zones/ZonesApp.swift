import SwiftUI
import GoogleMaps

@main
struct ZonesApp: App {
    @StateObject private var runTracker = RunTrackingService()
    @StateObject private var motion = CoreMotionService()
    @StateObject private var health = HealthKitService()
    @StateObject private var streaks = StreakService()
    @StateObject private var notifications = TerritoryNotificationService()

    init() {
        FirebaseBootstrap.configureIfNeeded()
        GMSServices.provideAPIKey(AppConfiguration.googleMapsAPIKey)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                runTracker: runTracker,
                motion: motion,
                health: health,
                streaks: streaks,
                notifications: notifications
            )
        }
    }
}
