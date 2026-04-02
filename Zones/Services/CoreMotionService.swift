import CoreMotion
import Foundation

@MainActor
final class CoreMotionService: ObservableObject {
    @Published private(set) var isRunningLikely = false
    @Published private(set) var cadenceStepsPerMinute: Double?

    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()

    func start() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            Task { @MainActor in
                self?.isRunningLikely = activity.running
            }
        }
    }

    func startPedometer(from date: Date) {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: date) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor in
                if let cadence = data.currentCadence?.doubleValue, cadence > 0 {
                    self?.cadenceStepsPerMinute = cadence * 60.0
                }
            }
        }
    }

    func stop() {
        activityManager.stopActivityUpdates()
        pedometer.stopUpdates()
    }
}
