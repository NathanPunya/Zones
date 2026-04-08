import ActivityKit
import Combine
import Foundation

/// Starts a Live Activity while a run is recording: Dynamic Island on supported iPhones, lock screen / banner elsewhere.
@MainActor
final class RunLiveActivityCoordinator: ObservableObject {
    private var activity: Activity<RunTrackingActivityAttributes>?
    private var startedAt: Date?
    private var cancellables = Set<AnyCancellable>()
    private weak var runTracker: RunTrackingService?
    /// Drives a once-per-second `ContentState` update so the lock screen / Island timer advances even when GPS is still.
    private var durationTickTask: Task<Void, Never>?

    func bind(runTracker: RunTrackingService) {
        self.runTracker = runTracker
        cancellables.removeAll()
        stopDurationTicker()

        runTracker.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                guard let self else { return }
                Task { await self.handleRecordingChange(recording, runTracker: runTracker) }
            }
            .store(in: &cancellables)

        // “Loop closed” should show right away; distance/duration otherwise refresh on the 1s ticker.
        runTracker.$loopClosed
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, let runTracker = self.runTracker,
                      runTracker.isRecording, self.activity != nil else { return }
                Task { await self.pushStateFromTracker() }
            }
            .store(in: &cancellables)
    }

    private func handleRecordingChange(_ recording: Bool, runTracker: RunTrackingService) async {
        if recording {
            await startIfNeeded(runTracker: runTracker)
        } else {
            await endActivity()
        }
    }

    private func startIfNeeded(runTracker: RunTrackingService) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else {
            await pushStateFromTracker()
            startDurationTicker()
            return
        }
        startedAt = Date()
        let state = RunTrackingActivityAttributes.ContentState(
            distanceMeters: runTracker.distanceMeters,
            durationSeconds: 0,
            loopClosed: runTracker.loopClosed
        )
        do {
            activity = try Activity.request(
                attributes: RunTrackingActivityAttributes(),
                contentState: state,
                pushType: nil
            )
            startDurationTicker()
        } catch {
            #if DEBUG
            print("Live Activity start failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func startDurationTicker() {
        stopDurationTicker()
        durationTickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let runTracker = self.runTracker,
                      runTracker.isRecording, self.activity != nil else { return }
                await self.pushStateFromTracker()
            }
        }
    }

    private func stopDurationTicker() {
        durationTickTask?.cancel()
        durationTickTask = nil
    }

    private func pushStateFromTracker() async {
        guard let runTracker else { return }
        await pushState(distanceMeters: runTracker.distanceMeters, loopClosed: runTracker.loopClosed)
    }

    private func pushState(distanceMeters: Double, loopClosed: Bool) async {
        guard let activity else { return }
        let duration: Int = {
            guard let t = startedAt else { return 0 }
            return Int(Date().timeIntervalSince(t))
        }()
        let state = RunTrackingActivityAttributes.ContentState(
            distanceMeters: distanceMeters,
            durationSeconds: duration,
            loopClosed: loopClosed
        )
        await activity.update(using: state)
    }

    private func endActivity() async {
        stopDurationTicker()
        startedAt = nil
        guard let activity else { return }
        let final = RunTrackingActivityAttributes.ContentState(
            distanceMeters: runTracker?.distanceMeters ?? 0,
            durationSeconds: 0,
            loopClosed: runTracker?.loopClosed ?? false
        )
        await activity.end(using: final, dismissalPolicy: .immediate)
        self.activity = nil
    }
}
