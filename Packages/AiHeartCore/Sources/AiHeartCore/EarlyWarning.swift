import Foundation

// Her own early signs (docs/18). The app can only see sleep and the energy she taps, so it checks
// those against her own previous 28 days and says what it saw in plain words. It never names a
// state, never gives advice, and never says anything is wrong: the notice is a prompt to look at
// the list she wrote with her clinician. The rest of her signs stay hers to check.

public enum EarlyWarning {
    /// Her usual comes from the 28 days before the last 3, and needs at least 14 days of data.
    public static let baselineDays = 28
    public static let minBaselineDays = 14
    public static let recentDays = 3
    /// Nights short by at least this many hours, on at least `minNights` of the last 3.
    public static let sleepDropHours = 1.5
    public static let shiftHours = 1.5
    public static let minNights = 2
    /// Energy taps (not model guesses) averaging this far above her usual, from at least 3 taps.
    public static let energyRise = 0.4
    public static let minEnergyPoints = 3
    /// Quiet stretch after a notice, in days.
    public static let quietDays = 7

    public struct Notice: Equatable, Sendable {
        public enum Kind: String, Sendable { case shortNights, timingShift, energyUp }
        public let kind: Kind
        /// A plain description of what was seen. No label, no advice.
        public let text: String
    }

    public struct EnergyPoint: Equatable, Sendable {
        public let day: AnchoredDay
        public let arousal: Double
        public init(day: AnchoredDay, arousal: Double) { self.day = day; self.arousal = arousal }
    }

    /// Her own energy taps. Points the model guessed from her writing are left out.
    public static func energyPoints(_ entries: [Entry], dayStart: Int) -> [EnergyPoint] {
        entries.compactMap { e in
            guard e.status != .released, !e.moodGuessed, let a = e.arousal, e.valence != nil else { return nil }
            return EnergyPoint(day: DayAnchor.day(for: e.createdAt, timeZone: e.timeZone, dayStartHour: dayStart), arousal: a)
        }
    }

    /// What the app can see right now, each against her own usual. Empty when there is nothing to say
    /// or too little data to say it.
    public static func notices(nights: [NightSample], energy: [EnergyPoint], today: AnchoredDay) -> [Notice] {
        let t = today.ordinal
        let recent = (t - recentDays + 1)...t
        let before = (t - recentDays - baselineDays + 1)...(t - recentDays)
        var out: [Notice] = []

        let byDay = Dictionary(nights.map { ($0.day.ordinal, $0) }, uniquingKeysWith: { a, _ in a })
        let recentNights = recent.compactMap { byDay[$0] }
        let prior = before.compactMap { byDay[$0] }

        // a) Sleep length down.
        let priorMins = prior.compactMap(\.sleepMin)
        if priorMins.count >= minBaselineDays {
            let usual = Baselines.median(priorMins)
            let shortfalls = recentNights.compactMap(\.sleepMin).map { (usual - $0) / 60 }.filter { $0 >= sleepDropHours }
            if shortfalls.count >= minNights {
                let avg = shortfalls.reduce(0, +) / Double(shortfalls.count)
                out.append(Notice(kind: .shortNights,
                                  text: "\(count(shortfalls.count).capitalized) short nights: about \(hours(avg)) h under your usual"))
            }
        }

        // b) Sleep timing moved, the same way on at least 2 of the last 3 nights.
        let priorMids = prior.compactMap(\.midpoint)
        if priorMids.count >= minBaselineDays {
            let usual = Baselines.median(priorMids)
            let shifts = recentNights.compactMap(\.midpoint).map { ($0 - usual) / 60 }
            let later = shifts.filter { $0 >= shiftHours }, earlier = shifts.filter { $0 <= -shiftHours }
            let (moved, word) = later.count >= earlier.count ? (later, "later") : (earlier, "earlier")
            if moved.count >= minNights {
                let avg = moved.map(abs).reduce(0, +) / Double(moved.count)
                out.append(Notice(kind: .timingShift,
                                  text: "Your sleep has been about \(hours(avg)) h \(word) than your usual on \(count(moved.count)) of the last 3 nights"))
            }
        }

        // c) Energy taps up.
        let priorPoints = energy.filter { before.contains($0.day.ordinal) }
        let recentEnergy = energy.filter { recent.contains($0.day.ordinal) }.map(\.arousal)
        if Set(priorPoints.map(\.day.ordinal)).count >= minBaselineDays, recentEnergy.count >= minEnergyPoints {
            let usual = priorPoints.map(\.arousal).reduce(0, +) / Double(priorPoints.count)
            let now = recentEnergy.reduce(0, +) / Double(recentEnergy.count)
            if now - usual >= energyRise {
                out.append(Notice(kind: .energyUp, text: "Your energy taps have been higher than usual"))
            }
        }
        return out
    }

    /// One notice per stretch: only when she has the watch on, Pause everything is off, and it has
    /// been at least 7 days since the last one (`signsNoticedDay` is a day ordinal, 0 for never).
    public static func isDue(watch: Bool, paused: Bool, lastNoticedDay: Int, today: AnchoredDay) -> Bool {
        guard watch, !paused else { return false }
        return lastNoticedDay <= 0 || today.ordinal >= lastNoticedDay + quietDays
    }

    /// Older free-text early signs split into one item per line (or per semicolon), bullets removed.
    public static func splitOlderNotes(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "\n" || $0 == ";" }).compactMap { part in
            var s = part.trimmingCharacters(in: .whitespacesAndNewlines)
            while let f = s.first, "-•*–".contains(f) {
                s.removeFirst()
                s = s.trimmingCharacters(in: .whitespaces)
            }
            return s.isEmpty ? nil : s
        }
    }

    // Round to the nearest half hour for display: "1.5", "2", "2.5".
    static func hours(_ h: Double) -> String {
        let r = (h * 2).rounded() / 2
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }

    static func count(_ n: Int) -> String { n == 2 ? "two" : n == 3 ? "three" : "\(n)" }
}

/// Mood points the outlook and patterns learn from: her own taps only. Points the on-device model
/// guessed from her writing (`Entry.moodGuessed`) stay in charts but never train anything.
public enum TrainingMood {
    public struct Day: Equatable, Sendable {
        public let valence: Double
        /// Nil when none of that day's points had an energy value.
        public let arousal: Double?
    }

    public static func perDay(_ entries: [Entry], dayStart: Int) -> [AnchoredDay: Day] {
        var sums: [AnchoredDay: (v: Double, vn: Double, a: Double, an: Double)] = [:]
        for e in entries where !e.moodGuessed {
            guard let v = e.valence else { continue }
            let d = DayAnchor.day(for: e.createdAt, timeZone: e.timeZone, dayStartHour: dayStart)
            var s = sums[d] ?? (0, 0, 0, 0)
            s.v += v; s.vn += 1
            if let a = e.arousal { s.a += a; s.an += 1 }
            sums[d] = s
        }
        return sums.mapValues { Day(valence: $0.v / $0.vn, arousal: $0.an > 0 ? $0.a / $0.an : nil) }
    }
}
