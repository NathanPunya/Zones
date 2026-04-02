import Foundation
import FirebaseCore

enum FirebaseBootstrap {
    static func configureIfNeeded() {
        guard AppConfiguration.hasFirebasePlist else { return }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }
}
