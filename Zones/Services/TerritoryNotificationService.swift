import Foundation
import UserNotifications

@MainActor
final class TerritoryNotificationService: ObservableObject {
    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func notifyZoneClaimed(area: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Zone captured"
        content.body = String(format: "You claimed ~%.0f m² of new territory.", area)
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleStreakReminderIfNeeded(streakDays: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Keep the streak alive"
        content.body = "You’re on a \(streakDays)-day streak — run a loop to defend your map."
        var date = DateComponents()
        date.hour = 18
        date.minute = 30
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: "zones.streak.reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
