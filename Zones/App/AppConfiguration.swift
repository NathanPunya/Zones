import Foundation

enum AppConfiguration {
    /// Prefer key from `.env` (injected at build time via `Generated/EnvSecrets.swift`), then Info.plist `GMSApiKey`.
    static var googleMapsAPIKey: String {
        let fromEnv = EnvSecrets.googleMapsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromEnv.isEmpty { return fromEnv }
        return (Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? ""
    }

    static var hasGoogleMapsKey: Bool {
        let key = googleMapsAPIKey
        guard !key.isEmpty else { return false }
        if key == "GOOGLE_MAPS_API_KEY" || key == "$(GOOGLE_MAPS_API_KEY)" { return false }
        return !key.contains("REPLACE_WITH")
    }

    static var hasFirebasePlist: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }
}
