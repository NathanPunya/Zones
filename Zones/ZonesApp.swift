import SwiftUI

@main
struct ZonesApp: App {
    @UIApplicationDelegateAdaptor(ZonesAppDelegate.self) private var appDelegate

    @StateObject private var runTracker = RunTrackingService()
    @StateObject private var motion = CoreMotionService()
    @StateObject private var health = HealthKitService()
    @StateObject private var streaks = StreakService()
    @StateObject private var notifications = TerritoryNotificationService()
    @StateObject private var diagnosticsLog = AppDiagnosticsLogStore()
    @StateObject private var runLiveActivity = RunLiveActivityCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView(
                runTracker: runTracker,
                motion: motion,
                health: health,
                streaks: streaks,
                notifications: notifications,
                diagnosticsLog: diagnosticsLog
            )
            .onAppear {
                runLiveActivity.bind(runTracker: runTracker)
            }
        }
    }
}
