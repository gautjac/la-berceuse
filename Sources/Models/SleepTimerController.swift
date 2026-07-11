import Foundation
import Combine
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Drives the sleep timer at runtime: ticks the pure `SleepTimer` value, pushes
/// the fade multiplier into `SoundEngine`, and stops everything at silence.
/// Lives app-wide so the timer keeps running as the user moves between tabs.
@MainActor
public final class SleepTimerController: ObservableObject {
    public static let shared = SleepTimerController()

    @Published public private(set) var timer = SleepTimer(total: 0)
    @Published public private(set) var running = false
    /// Increments each time a timer reaches silence. A monotonic signal (unlike
    /// `timer.isFinished`, which flips back to false in the same tick when the
    /// timer resets) so views — e.g. the nidra player — can react reliably.
    @Published public private(set) var completions = 0

    private var ticker: AnyCancellable?
    private var lastTick = Date()
    private let fadeSeconds: Double = 60

    #if canImport(ActivityKit)
    private var activity: Activity<SleepTimerAttributes>?
    #endif

    private init() {}

    public var isActive: Bool { running && timer.isActive }
    public var clockString: String { timer.clockString }
    public var remaining: Double { timer.remaining }

    /// Start (or restart) the timer for `minutes`. 0 cancels it.
    public func start(minutes: Int) {
        cancel(resetVolume: false)
        guard minutes > 0 else { return }
        timer = SleepTimer(total: Double(minutes) * 60, fade: fadeSeconds)
        running = true
        lastTick = Date()
        SoundEngine.shared.masterMultiplier = 1
        MusicEngine.shared.masterMultiplier = 1
        ticker = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
        startLiveActivity(endDate: Date().addingTimeInterval(Double(minutes) * 60))
    }

    public func cancel(resetVolume: Bool = true) {
        ticker?.cancel()
        ticker = nil
        running = false
        timer = SleepTimer(total: 0)
        if resetVolume {
            SoundEngine.shared.masterMultiplier = 1
            MusicEngine.shared.masterMultiplier = 1
        }
        endLiveActivity()
    }

    // MARK: - Live Activity (lock-screen / Dynamic Island countdown)

    /// One request at start, one end at silence — the countdown itself renders
    /// on the lock screen via `Text(timerInterval:)`, no per-tick updates.
    private func startLiveActivity(endDate: Date) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endLiveActivity()
        activity = try? Activity.request(
            attributes: SleepTimerAttributes(),
            content: .init(state: .init(endDate: endDate), staleDate: endDate)
        )
        #endif
    }

    private func endLiveActivity() {
        #if canImport(ActivityKit)
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        #endif
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        timer = timer.advanced(by: dt)
        // The same equal-power fade drives both the ambient layers and the
        // generative music so they ebb to silence together.
        SoundEngine.shared.masterMultiplier = timer.volumeMultiplier
        MusicEngine.shared.masterMultiplier = timer.volumeMultiplier
        if timer.isFinished {
            completions += 1
            SoundEngine.shared.stopAll()
            MusicEngine.shared.stop()
            cancel(resetVolume: true)
        }
    }
}
