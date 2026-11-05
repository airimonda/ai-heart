import AiHeartCore
import HealthKit
import SwiftData
import SwiftUI

/// Reads Apple Health and builds one DaySummary per anchored day. Nothing leaves the device
/// (docs/04). The only writes are the vitals she types in the morning check-in (owner,
/// 2026-11-01): heart rate, weight and blood pressure.
@MainActor @Observable
final class HealthService {
    static let shared = HealthService()

    private let store = HKHealthStore()
    var syncing = false
    var lastSync: Date?
    var lastError: String?
    /// True once she has been asked. iOS never reveals whether read access was granted.
    var asked = UserDefaults.standard.bool(forKey: "health.asked")

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis), HKCategoryType(.menstrualFlow), HKWorkoutType.workoutType()]
        let quantities: [HKQuantityTypeIdentifier] = [
            .restingHeartRate, .heartRateVariabilitySDNN, .respiratoryRate, .appleSleepingWristTemperature,
            .stepCount, .activeEnergyBurned, .basalEnergyBurned, .appleExerciseTime, .heartRate,
        ]
        for q in quantities { types.insert(HKQuantityType(q)) }
        return types
    }

    private var shareTypes: Set<HKSampleType> {
        [HKQuantityType(.heartRate), HKQuantityType(.bodyMass),
         HKQuantityType(.bloodPressureSystolic), HKQuantityType(.bloodPressureDiastolic)]
    }

    /// Saves what she typed to Apple Health. Asks for write access the first time.
    func saveVitals(heartRate: Double?, weightKg: Double?, bp: (Double, Double)?, at date: Date = .now) async {
        guard available else { return }
        try? await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        var samples: [HKObject] = []
        let meta: [String: Any] = [HKMetadataKeyWasUserEntered: true]
        if let hr = heartRate {
            samples.append(HKQuantitySample(type: HKQuantityType(.heartRate), quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: hr),
                                            start: date, end: date, metadata: meta))
        }
        if let w = weightKg {
            samples.append(HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: w),
                                            start: date, end: date, metadata: meta))
        }
        if let (sys, dia) = bp {
            let mm = HKUnit.millimeterOfMercury()
            let s = HKQuantitySample(type: HKQuantityType(.bloodPressureSystolic), quantity: HKQuantity(unit: mm, doubleValue: sys), start: date, end: date)
            let d = HKQuantitySample(type: HKQuantityType(.bloodPressureDiastolic), quantity: HKQuantity(unit: mm, doubleValue: dia), start: date, end: date)
            samples.append(HKCorrelation(type: HKCorrelationType(.bloodPressure), start: date, end: date, objects: [s, d], metadata: meta))
        }
        guard !samples.isEmpty else { return }
        do { try await store.save(samples); NSLog("AiHeartHealth vitals saved: %d", samples.count) }
        catch { NSLog("AiHeartHealth vitals save failed") }
    }

    func requestAccess() async {
        guard available else { return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            asked = true
            UserDefaults.standard.set(true, forKey: "health.asked")
            // Asked together, so there is one moment of permission prompts, not several.
            await WorkoutService.shared.requestNotificationPermission()
        } catch {
            lastError = "Apple Health did not respond. You can try again."
        }
    }

    /// Rebuilds the last `days` summaries. Recomputable by design (docs/02), so a full
    /// rebuild of a short window is simpler and safer than incremental patching.
    static let fullKey = "health.fullHistoryRead"
    /// True once all of her history has been read; later reads cover recent days only.
    var fullHistoryRead: Bool { UserDefaults.standard.bool(forKey: Self.fullKey) }

    /// First time: everything Health has (up to 10 years). After that: the last 14 days,
    /// which is enough to catch late-arriving Watch data.
    func sync(context: ModelContext, dayStartHour: Int = 4) async {
        let days: Int
        if fullHistoryRead {
            days = 14
        } else {
            let earliest = store.earliestPermittedSampleDate()
            days = min(3650, max(120, Int(Date().timeIntervalSince(earliest) / 86400) + 1))
        }
        await sync(context: context, days: days, dayStartHour: dayStartHour)
        if !syncing, lastError == nil, lastSync != nil { UserDefaults.standard.set(true, forKey: Self.fullKey) }
    }

    /// Reads all history again, for when she wants a fresh rebuild.
    func rereadAll(context: ModelContext, dayStartHour: Int = 4) async {
        UserDefaults.standard.set(false, forKey: Self.fullKey)
        await sync(context: context, dayStartHour: dayStartHour)
    }

    func sync(context: ModelContext, days: Int, dayStartHour: Int = 4) async {
        guard available, asked, !syncing else { return }
        // Sample data is for demos; never mix it with real readings.
        if DemoData.isOn(context) { return }
        syncing = true
        defer { syncing = false }
        let tz = TimeZone.current
        var cal = Calendar.current
        cal.timeZone = tz
        let now = Date()
        let todayStart = cal.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: now) ?? now
        let anchor = todayStart > now ? cal.date(byAdding: .day, value: -1, to: todayStart)! : todayStart
        let start = cal.date(byAdding: .day, value: -days, to: anchor)!

        var rows: [String: Partial] = [:]
        func row(_ d: AnchoredDay) -> Partial { rows[d.key] ?? Partial() }

        do {
            // Sleep, by the day she wakes into. Union of intervals across sources.
            let sleepStart = start.addingTimeInterval(-18 * 3600)
            let sleep = try await HKSampleQueryDescriptor(
                predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                             predicate: HKQuery.predicateForSamples(withStart: sleepStart, end: now))],
                sortDescriptors: [SortDescriptor(\.startDate)]
            ).result(for: store)
            var byDay: [AnchoredDay: [HKCategorySample]] = [:]
            for s in sleep { byDay[SleepMath.wakeDay(end: s.endDate, timeZone: tz), default: []].append(s) }
            for (day, samples) in byDay {
                func minutes(_ values: Set<Int>) -> Double? {
                    let iv = samples.filter { values.contains($0.value) }.map { SleepMath.Interval(start: $0.startDate, end: $0.endDate) }
                    return iv.isEmpty ? nil : SleepMath.minutes(iv)
                }
                let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                        HKCategoryValueSleepAnalysis.asleepREM.rawValue]
                var r = row(day)
                r.sleepMin = minutes(asleep)
                r.sleepSource = r.sleepMin == nil ? nil : "asleep"
                // Without a watch, the iPhone's sleep schedule records only time in bed.
                if r.sleepMin == nil, let inBed = minutes([HKCategoryValueSleepAnalysis.inBed.rawValue]) {
                    r.sleepMin = inBed
                    r.sleepSource = "inBed"
                }
                r.deep = minutes([HKCategoryValueSleepAnalysis.asleepDeep.rawValue])
                r.rem = minutes([HKCategoryValueSleepAnalysis.asleepREM.rawValue])
                r.core = minutes([HKCategoryValueSleepAnalysis.asleepCore.rawValue])
                r.awake = minutes([HKCategoryValueSleepAnalysis.awake.rawValue])
                rows[day.key] = r
            }

            // Wrist temperature, one reading per night, by wake day.
            let temps = try await HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: HKQuantityType(.appleSleepingWristTemperature),
                                             predicate: HKQuery.predicateForSamples(withStart: sleepStart, end: now))],
                sortDescriptors: []
            ).result(for: store)
            for t in temps {
                let day = SleepMath.wakeDay(end: t.endDate, timeZone: tz)
                var r = row(day)
                r.wristTemp = t.quantity.doubleValue(for: .degreeCelsius())
                rows[day.key] = r
            }

            // Menstrual flow. Health stores it per calendar day, so use the calendar day of the
            // sample's middle rather than the sleep-anchored day.
            let flows = try await HKSampleQueryDescriptor(
                predicates: [.categorySample(type: HKCategoryType(.menstrualFlow),
                                             predicate: HKQuery.predicateForSamples(withStart: start, end: now))],
                sortDescriptors: []
            ).result(for: store)
            for f in flows {
                let mid = f.startDate.addingTimeInterval(f.endDate.timeIntervalSince(f.startDate) / 2)
                let c = cal.dateComponents([.year, .month, .day], from: mid)
                let day = AnchoredDay(year: c.year!, month: c.month!, day: c.day!)
                // HKCategoryValueMenstrualFlow: 1 unspecified, 2 light, 3 medium, 4 heavy, 5 none.
                let level = f.value == 5 ? 0 : f.value
                var r = row(day)
                r.flow = max(r.flow ?? 0, level)
                rows[day.key] = r
            }

            // Daily statistics on the anchored day boundary.
            let perMinute = HKUnit.count().unitDivided(by: .minute())
            let stats: [(HKQuantityTypeIdentifier, HKStatisticsOptions, HKUnit, WritableKeyPath<Partial, Double?>)] = [
                (.stepCount, .cumulativeSum, .count(), \.steps),
                (.activeEnergyBurned, .cumulativeSum, .kilocalorie(), \.active),
                (.basalEnergyBurned, .cumulativeSum, .kilocalorie(), \.basal),
                (.appleExerciseTime, .cumulativeSum, .minute(), \.exercise),
                (.restingHeartRate, .discreteAverage, perMinute, \.rhr),
                (.heartRateVariabilitySDNN, .discreteAverage, .secondUnit(with: .milli), \.hrv),
                (.respiratoryRate, .discreteAverage, perMinute, \.resp),
            ]
            for (id, option, unit, path) in stats {
                let collection = try await HKStatisticsCollectionQueryDescriptor(
                    predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: now)),
                    options: option, anchorDate: anchor, intervalComponents: DateComponents(day: 1)
                ).result(for: store)
                collection.enumerateStatistics(from: start, to: now) { s, _ in
                    let q = option == .cumulativeSum ? s.sumQuantity() : s.averageQuantity()
                    guard let q else { return }
                    let day = DayAnchor.day(for: s.startDate.addingTimeInterval(3600), timeZone: tz, dayStartHour: dayStartHour)
                    var r = rows[day.key] ?? Partial()
                    r[keyPath: path] = q.doubleValue(for: unit)
                    rows[day.key] = r
                }
            }
        } catch {
            lastError = "Could not read Apple Health just now."
            return
        }

        // Upsert, enforcing one row per day in code.
        let existing = (try? context.fetch(FetchDescriptor<DaySummary>())) ?? []
        var byKey: [String: DaySummary] = [:]
        for s in existing {
            if byKey[s.dayKey] == nil { byKey[s.dayKey] = s } else { context.delete(s) }
        }
        let device = UIDevice.current.identifierForVendor?.uuidString ?? ""
        for (key, p) in rows {
            guard let day = AnchoredDay(key: key) else { continue }
            let s = byKey[key] ?? { let n = DaySummary(day: day, timeZone: tz); context.insert(n); return n }()
            // Her own check-in stays unless a watch recorded real sleep for that night.
            if s.sleepSourceRaw != "manual" || p.sleepSource == "asleep" {
                s.sleepMin = p.sleepMin; s.sleepSourceRaw = p.sleepSource
            }
            s.sleepDeepMin = p.deep; s.sleepRemMin = p.rem; s.sleepCoreMin = p.core; s.awakeMin = p.awake
            // Without a watch, her typed morning heart rate stands in for resting heart rate.
            s.restingHR = p.rhr ?? s.manualHR; s.hrvSDNN = p.hrv; s.respRate = p.resp; s.wristTempC = p.wristTemp
            s.steps = p.steps; s.activeKcal = p.active; s.basalKcal = p.basal; s.exerciseMin = p.exercise
            s.menstrualFlow = p.flow
            s.deviceId = device
            s.updatedAt = .now
        }
        ExerciseFill.run(context: context, dayStartHour: dayStartHour)
        try? context.save()
        lastSync = .now
        lastError = nil
    }

    private struct Partial {
        var sleepMin, deep, rem, core, awake: Double?
        var sleepSource: String?
        var rhr, hrv, resp, wristTemp: Double?
        var steps, active, basal, exercise: Double?
        var flow: Int?
    }
}
