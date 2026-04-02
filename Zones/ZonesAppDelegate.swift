import GoogleMaps
import UIKit

/// Configures Firebase and Maps before any `@StateObject` runs (see `ZonesApp`).
final class ZonesAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.configureIfNeeded()
        GMSServices.provideAPIKey(AppConfiguration.googleMapsAPIKey)
        return true
    }
}
