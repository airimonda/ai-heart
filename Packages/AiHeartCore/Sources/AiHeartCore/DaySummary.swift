import Foundation
import SwiftData

/// One per anchored day, derived from HealthKit on the iPhone (docs/02). Recomputable,
/// so it may be rebuilt at any time. Values in SI units. Uniqueness by `dayKey` is
/// enforced in code (no unique constraints with CloudKit).
@Model
public final class DaySummary {
    public var syncId: UUID = UUID()
    public var updatedAt: Date = Date()
    public var deviceId: String = ""

    /// "yyyy-MM-dd" of the anchored day.
    public var dayKey: String = ""
    public var tz: String = TimeZone.current.identifier

    @Attribute(.allowsCloudEncryption) public var sleepMin: Double?
    @Attribute(.allowsCloudEncryption) public var sleepDeepMin: Double?
    @Attribute(.allowsCloudEncryption) public var sleepRemMin: Double?
    @Attribute(.allowsCloudEncryption) public var sleepCoreMin: Double?
    @Attribute(.allowsCloudEncryption) public var awakeMin: Double?
    /// Where sleep came from: "asleep" (watch), "inBed" (iPhone sleep schedule) or "manual".
    public var sleepSourceRaw: String?
    @Attribute(.allowsCloudEncryption) public var bedtime: Date?
    @Attribute(.allowsCloudEncryption) public var wakeTime: Date?
    /// How rested she felt, 1 to 5, from the morning check-in.
    @Attribute(.allowsCloudEncryption) public var rested: Int?
    @Attribute(.allowsCloudEncryption) public var restingHR: Double?
    // Typed by her in the morning check-in, while she has no watch (owner, 2026-11-01).
    @Attribute(.allowsCloudEncryption) public var manualHR: Double?
    @Attribute(.allowsCloudEncryption) public var weightKg: Double?
    @Attribute(.allowsCloudEncryption) public var systolic: Double?
    @Attribute(.allowsCloudEncryption) public var diastolic: Double?
    /// Warning signs she ticked in the check-in (UrgentSigns.Sign raw values).
    @Attribute(.allowsCloudEncryption) public var warningSigns: [String] = []
    @Attribute(.allowsCloudEncryption) public var hrvSDNN: Double?
    @Attribute(.allowsCloudEncryption) public var respRate: Double?
    /// Absolute sleeping wrist temperature in °C. The delta is computed against her own
    /// baseline when shown, so a baseline change never rewrites stored data.
    @Attribute(.allowsCloudEncryption) public var wristTempC: Double?
    @Attribute(.allowsCloudEncryption) public var steps: Double?
    @Attribute(.allowsCloudEncryption) public var activeKcal: Double?
    @Attribute(.allowsCloudEncryption) public var basalKcal: Double?
    @Attribute(.allowsCloudEncryption) public var exerciseMin: Double?

    /// Menstrual flow from Health: 0 none, 1 unspecified, 2 light, 3 medium, 4 heavy.
    @Attribute(.allowsCloudEncryption) public var menstrualFlow: Int?

    // Derived by the cycle engine on the device that has Health data.
    public var cycleDay: Int?
    public var phaseRaw: String?

    public init(day: AnchoredDay, timeZone: TimeZone = .current) {
        self.dayKey = day.key
        self.tz = timeZone.identifier
    }

    public var day: AnchoredDay? { AnchoredDay(key: dayKey) }

    public var totalKcal: Double? {
        guard activeKcal != nil || basalKcal != nil else { return nil }
        return (activeKcal ?? 0) + (basalKcal ?? 0)
    }

    public var isEmpty: Bool {
        [sleepMin, restingHR, hrvSDNN, respRate, wristTempC, steps, activeKcal, exerciseMin].allSatisfy { $0 == nil }
    }

    public func value(_ signal: Signal) -> Double? {
        switch signal {
        case .sleep: sleepMin
        case .restingHR: restingHR
        case .hrv: hrvSDNN
        case .wristTemp: wristTempC
        case .breathing: respRate
        case .steps: steps
        case .activeKcal: activeKcal
        case .exercise: exerciseMin
        }
    }
}

public enum Signal: String, CaseIterable, Sendable {
    case sleep, restingHR, hrv, wristTemp, breathing, steps, activeKcal, exercise

    public var title: String {
        switch self {
        case .sleep: "Sleep"
        case .restingHR: "Resting HR"
        case .hrv: "HRV"
        case .wristTemp: "Wrist temp"
        case .breathing: "Breathing"
        case .steps: "Steps"
        case .activeKcal: "Active calories"
        case .exercise: "Exercise"
        }
    }

    /// Smallest spread treated as meaningful, so a very steady signal does not make
    /// tiny changes look large.
    var minSpread: Double {
        switch self {
        case .sleep: 15
        case .restingHR: 1.5
        case .hrv: 3
        case .wristTemp: 0.1
        case .breathing: 0.4
        case .steps: 500
        case .activeKcal: 30
        case .exercise: 5
        }
    }
}

extension AnchoredDay {
    public var key: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public init?(key: String) {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// Days since 1970-01-01, for window arithmetic. Calendar math in UTC, so it is
    /// independent of the device time zone.
    public var ordinal: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: year, month: month, day: day))!
        return Int((date.timeIntervalSince1970 / 86400).rounded())
    }

    public init(ordinal: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(ordinal) * 86400))
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public func adding(days: Int) -> AnchoredDay { AnchoredDay(ordinal: ordinal + days) }
}
