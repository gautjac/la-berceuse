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
    private var heartRateType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .heartRate)
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

    /// Ask only for heart-rate *read* access — used by the generative-music
    /// engine to gently entrain tempo. Independent of the sleep authorization so
    /// a listener can grant one without the other. No-ops gracefully when denied.
    public func requestHeartRateAuthorization() async -> Bool {
        guard isAvailable, let heartRateType else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [heartRateType])
            return true
        } catch {
            return false
        }
    }

    /// The most recent heart-rate sample (bpm) within the last 15 minutes, or
    /// nil if unavailable / not authorized / stale. Device-only in practice.
    public func latestHeartRate() async -> Double? {
        guard isAvailable, let heartRateType else { return nil }
        let since = Date().addingTimeInterval(-15 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let q = HKSampleQuery(sampleType: heartRateType, predicate: predicate,
                                  limit: 1, sortDescriptors: sort) { _, samples, _ in
                guard let s = (samples as? [HKQuantitySample])?.first else {
                    cont.resume(returning: nil); return
                }
                let bpm = s.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                cont.resume(returning: bpm)
            }
            store.execute(q)
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

    /// Read the last `count` nights of sleep, one record per morning, for the
    /// carnet de nuit. Returns [] when unavailable / not authorized / no data.
    public func nights(last count: Int) async -> [NightRecord] {
        guard isAvailable, let sleepType, count > 0 else { return [] }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(count + 1), to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        return await withCheckedContinuation { (cont: CheckedContinuation<[NightRecord], Never>) in
            let q = HKSampleQuery(sampleType: sleepType, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let cats = samples as? [HKCategorySample], !cats.isEmpty else {
                    cont.resume(returning: [])
                    return
                }
                // Bucket asleep time by the morning each segment ended toward.
                var byMorning: [Date: TimeInterval] = [:]
                for s in cats where asleepValues.contains(s.value) {
                    let morning = cal.startOfDay(for: CarnetMath.nightMorning(for: s.startDate, calendar: cal))
                    byMorning[morning, default: 0] += s.endDate.timeIntervalSince(s.startDate)
                }
                let records = byMorning
                    .map { NightRecord(morning: $0.key, asleepHours: $0.value / 3600.0) }
                    .sorted { $0.morning < $1.morning }
                    .suffix(count)
                cont.resume(returning: Array(records))
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
    public func requestHeartRateAuthorization() async -> Bool { false }
    public func latestHeartRate() async -> Double? { nil }
    public func lastNight() async -> SleepSummary? { nil }
    public func nights(last count: Int) async -> [NightRecord] { [] }
    public func logWindDown(start: Date, end: Date) async {}
    #endif
}
