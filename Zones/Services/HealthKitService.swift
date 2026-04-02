import Foundation
import HealthKit

@MainActor
final class HealthKitService: ObservableObject {
    @Published private(set) var isAuthorized = false

    private let health = HKHealthStore()

    private var typesToRead: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        ]
    }

    private var typesToShare: Set<HKSampleType> {
        [HKObjectType.workoutType()]
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await health.requestAuthorization(toShare: typesToShare, read: typesToRead)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
    }

    func saveZoneRun(distanceMeters: Double, start: Date, end: Date) async {
        guard isAuthorized else { return }
        let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: distanceMeters)
        let workout = HKWorkout(
            activityType: .running,
            start: start,
            end: end,
            workoutEvents: nil,
            totalEnergyBurned: nil,
            totalDistance: distanceQuantity,
            device: nil,
            metadata: [HKMetadataKeyWorkoutBrandName: "Zones"]
        )
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                health.save(workout) { _, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
            }
        } catch {
            #if DEBUG
            print("HealthKit save failed: \(error)")
            #endif
        }
    }

    func recentRunDistances(days: Int) async -> [Double] {
        guard isAuthorized else { return [] }
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.date(byAdding: .day, value: -days, to: Date()),
            end: Date()
        )
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let workouts = (samples as? [HKWorkout]) ?? []
                let distances = workouts.map { $0.totalDistance?.doubleValue(for: .meter()) ?? 0 }
                cont.resume(returning: distances)
            }
            health.execute(query)
        }
    }
}
