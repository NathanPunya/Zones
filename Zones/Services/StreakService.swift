import Foundation

final class StreakService: ObservableObject {
    @Published private(set) var currentStreakDays: Int = 0

    private let defaults = UserDefaults.standard
    private let keyLastDay = "zones.streak.lastRunDay"
    private let keyStreak = "zones.streak.count"

    init() {
        refreshFromStorage()
    }

    func refreshFromStorage() {
        currentStreakDays = defaults.integer(forKey: keyStreak)
    }

    /// Call when the user completes a qualifying run (e.g. zone claim or recorded session).
    func registerActivity(on date: Date = Date()) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        guard let last = defaults.object(forKey: keyLastDay) as? Date else {
            defaults.set(today, forKey: keyLastDay)
            defaults.set(1, forKey: keyStreak)
            refreshFromStorage()
            return
        }
        let lastDay = cal.startOfDay(for: last)
        if lastDay == today {
            refreshFromStorage()
            return
        }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: today), lastDay == yesterday {
            let next = defaults.integer(forKey: keyStreak) + 1
            defaults.set(next, forKey: keyStreak)
        } else {
            defaults.set(1, forKey: keyStreak)
        }
        defaults.set(today, forKey: keyLastDay)
        refreshFromStorage()
    }
}
