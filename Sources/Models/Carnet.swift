import Foundation

/// Le carnet de nuit — connects the rituals the app already logs with the sleep
/// HealthKit already reports, and distills the correlation into a few gentle
/// observations. All pure value math (dates in, numbers out) so it's testable;
/// the view turns the numbers into quiet sentences.

/// One night, keyed by the *morning* it ended (startOfDay of the wake date).
public struct NightRecord: Equatable, Sendable {
    public let morning: Date
    public let asleepHours: Double
    public init(morning: Date, asleepHours: Double) {
        self.morning = morning
        self.asleepHours = asleepHours
    }
}

public struct CarnetInsights: Equatable, Sendable {
    public var nightCount: Int = 0
    public var averageHours: Double = 0
    /// Nights preceded by at least one wind-down ritual.
    public var ritualNightCount: Int = 0
    public var ritualAverageHours: Double = 0
    public var plainAverageHours: Double = 0
    /// ritualAverage − plainAverage, in minutes (the headline number).
    public var ritualGainMinutes: Double = 0
    /// The most-practised ritual kind ("breath", "nidra", …), if any.
    public var favouriteKind: String?
    /// Consecutive ritual nights ending at the most recent night.
    public var currentStreak: Int = 0
    /// Per-night bars for the sparkline, oldest → newest.
    public var bars: [NightRecord] = []
}

public enum CarnetMath {
    /// The morning a session belongs to: anything from noon onward counts toward
    /// the *next* morning's night; small-hours sessions toward the same morning.
    public static func nightMorning(for sessionStart: Date, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: sessionStart)
        let day = calendar.startOfDay(for: sessionStart)
        if hour >= 12 {
            return calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return day
    }

    /// Correlate nights with the rituals that preceded them.
    /// `sessions` are (kind, startedAt) pairs from the ritual history.
    public static func insights(nights: [NightRecord],
                                sessions: [(kind: String, startedAt: Date)],
                                calendar: Calendar = .current) -> CarnetInsights {
        var out = CarnetInsights()
        let sorted = nights.sorted { $0.morning < $1.morning }
        out.bars = sorted
        out.nightCount = sorted.count
        guard !sorted.isEmpty else { return out }

        // Which mornings had a ritual the night before?
        var ritualMornings = Set<Date>()
        var kindCounts: [String: Int] = [:]
        for s in sessions {
            ritualMornings.insert(calendar.startOfDay(for: nightMorning(for: s.startedAt, calendar: calendar)))
            kindCounts[s.kind, default: 0] += 1
        }
        out.favouriteKind = kindCounts.max { $0.value < $1.value }?.key

        var ritualSum = 0.0, plainSum = 0.0
        var plainCount = 0
        for n in sorted {
            let key = calendar.startOfDay(for: n.morning)
            if ritualMornings.contains(key) {
                out.ritualNightCount += 1
                ritualSum += n.asleepHours
            } else {
                plainCount += 1
                plainSum += n.asleepHours
            }
        }
        out.averageHours = sorted.reduce(0) { $0 + $1.asleepHours } / Double(sorted.count)
        out.ritualAverageHours = out.ritualNightCount > 0 ? ritualSum / Double(out.ritualNightCount) : 0
        out.plainAverageHours = plainCount > 0 ? plainSum / Double(plainCount) : 0
        // The delta only means something with both kinds of night present.
        if out.ritualNightCount > 0 && plainCount > 0 {
            out.ritualGainMinutes = (out.ritualAverageHours - out.plainAverageHours) * 60
        }

        // Streak: walk back from the most recent night.
        for n in sorted.reversed() {
            if ritualMornings.contains(calendar.startOfDay(for: n.morning)) {
                out.currentStreak += 1
            } else { break }
        }
        return out
    }
}
