import Foundation
import Combine

/// Drives the sleep timer at runtime: ticks the pure `SleepTimer` value, pushes
/// the fade multiplier into `SoundEngine`, and stops everything at silence.
/// Lives app-wide so the timer keeps running as the user moves between tabs.
@MainActor
public final class SleepTimerController: ObservableObject {
    public static let shared = SleepTimerController()

    @Published public private(set) var timer = SleepTimer(total: 0)
    @Published public private(set) var running = false

    private var ticker: AnyCancellable?
    private var lastTick = Date()
    private let fadeSeconds: Double = 60

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
        ticker = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    public func cancel(resetVolume: Bool = true) {
        ticker?.cancel()
        ticker = nil
        running = false
        timer = SleepTimer(total: 0)
        if resetVolume { SoundEngine.shared.masterMultiplier = 1 }
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        timer = timer.advanced(by: dt)
        SoundEngine.shared.masterMultiplier = timer.volumeMultiplier
        if timer.isFinished {
            SoundEngine.shared.stopAll()
            cancel(resetVolume: true)
        }
    }
}
