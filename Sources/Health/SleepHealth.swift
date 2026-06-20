import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Last night's sleep, distilled to one gentle stat.
public struct SleepSummary: Sendable, Equatable {
    public let asleepHours: Double
    public let inBedHours: Double
    public let date: Date

    public var asleepHM: String {
        let h = Int(asleepHours)
        let m = Int((asleepHours - Double(h)) * 60)
        return "\(h) h \(String(format: "%02d", m))"
    }
}

/// Thin wrapper around HealthKit. Reads last night's sleepAnalysis and logs a
/// wind-down ritual as an HKCategory `inBed` segment (the closest analogue to
/// "mindful time before sleep" for a sleep app). Device-only behaviour; on the
/// simulator everything no-ops gracefully so the UI flow still demos.
public final class SleepHealth: @unchecked Sendable {
    public static let shared = SleepHealth()
    private init() {}

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    private var sleepType: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
    }

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func requestAuthorization() async -> Bool {
        guard isAvailable, let sleepType else { return false }
        let share: Set<HKSampleType> = [sleepType]
        let read: Set<HKObjectType> = [sleepType]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            return true
        } catch {
            return false
        }
    }

    /// Read last night's sleep. Returns nil if unavailable / not authorized /
    /// no data.
    public func lastNight() async -> SleepSummary? {
        guard isAvailable, let sleepType else { return nil }
        let cal = Calendar.current
        let now = Date()
        // Window: from noon yesterday to noon today (captures one night).
        let startOfToday = cal.startOfDay(for: now)
        guard let noonToday = cal.date(byAdding: .hour, value: 12, to: startOfToday),
              let noonYesterday = cal.date(byAdding: .day, value: -1, to: noonToday) else {
            return nil
        }
        let upper = min(now, noonToday)
        let predicate = HKQuery.predicateForSamples(withStart: noonYesterday, end: upper, options: [])

        return await withCheckedContinuation { (cont: CheckedContinuation<SleepSummary?, Never>) in
            let q = HKSampleQuery(sampleType: sleepType, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let cats = samples as? [HKCategorySample], !cats.isEmpty else {
                    cont.resume(returning: nil)
                    return
                }
                var asleep: TimeInterval = 0
                var inBed: TimeInterval = 0
                for s in cats {
                    let dur = s.endDate.timeIntervalSince(s.startDate)
                    switch s.value {
                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                        inBed += dur
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                         HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                         HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                         HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        asleep += dur
                    default:
                        break
                    }
                }
                if asleep == 0 && inBed == 0 {
                    cont.resume(returning: nil)
                    return
                }
                let summary = SleepSummary(
                    asleepHours: (asleep > 0 ? asleep : inBed) / 3600.0,
                    inBedHours: (inBed > 0 ? inBed : asleep) / 3600.0,
                    date: upper
                )
                cont.resume(returning: summary)
            }
            store.execute(q)
        }
    }

    /// Log a wind-down ritual that just ended as an `inBed` segment.
    public func logWindDown(start: Date, end: Date) async {
        guard isAvailable, let sleepType, end > start else { return }
        let sample = HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.inBed.rawValue,
            start: start, end: end
        )
        do { try await store.save(sample) } catch { /* non-fatal */ }
    }
    #else
    public var isAvailable: Bool { false }
    public func requestAuthorization() async -> Bool { false }
    public func lastNight() async -> SleepSummary? { nil }
    public func logWindDown(start: Date, end: Date) async {}
    #endif
}
