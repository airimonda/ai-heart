import Foundation

/// "Between tests" (owner, 2026-11-01): what she ticked in her weekly check, grouped by the
/// stretches between her blood tests, in her own words. No score, no chart.
public enum BetweenTests {
    public struct Check: Sendable {
        public let week: AnchoredDay
        /// Symptom name to strength (0 none, 1 some, 2 a lot).
        public let symptoms: [String: Int]
        public init(week: AnchoredDay, symptoms: [String: Int]) { self.week = week; self.symptoms = symptoms }
    }

    public struct Count: Sendable, Equatable {
        public let symptom: String
        public let weeks: Int
    }

    public struct Period: Sendable, Identifiable {
        public var id: String { start.key }
        /// Lab day that opens the stretch; nil for the time before her first lab.
        public let startLab: AnchoredDay?
        public let start: AnchoredDay
        /// Lab day that closes it; nil for the current stretch.
        public let endLab: AnchoredDay?
        /// Weekly checks she did in this stretch.
        public let checked: Int
        public let counts: [Count]
        public let doses: [(day: AnchoredDay, text: String)]

        /// Weeks in the stretch, rounded up.
        public func weeks(today: AnchoredDay) -> Int {
            max(1, Int((Double((endLab ?? today).ordinal - start.ordinal) / 7).rounded(.up)))
        }
    }

    /// Newest first. Symptoms ticked in fewer than `minWeeks` checks are left out to keep it short.
    public static func periods(checks: [Check], labDays: [AnchoredDay], doses: [(day: AnchoredDay, text: String)],
                               today: AnchoredDay, maxPeriods: Int = 4) -> [Period] {
        let labs = Array(Set(labDays)).sorted()
        var bounds: [(start: AnchoredDay, startLab: AnchoredDay?, end: AnchoredDay?)] = []
        if let first = labs.first, let earliest = checks.map(\.week).min(), earliest < first {
            bounds.append((earliest, nil, first))
        }
        for (i, l) in labs.enumerated() {
            bounds.append((l, l, i + 1 < labs.count ? labs[i + 1] : nil))
        }
        if labs.isEmpty, let earliest = checks.map(\.week).min() { bounds.append((earliest, nil, nil)) }

        let out: [Period] = bounds.map { b in
            let inside = checks.filter { c in c.week >= b.start && (b.end.map { e in c.week < e } ?? true) }
            var tally: [String: Int] = [:]
            for c in inside { for (s, v) in c.symptoms where v > 0 { tally[s, default: 0] += 1 } }
            let counts = tally.map { Count(symptom: $0.key, weeks: $0.value) }
                .sorted { $0.weeks != $1.weeks ? $0.weeks > $1.weeks : $0.symptom < $1.symptom }
            let ds = doses.filter { d in d.day >= b.start && (b.end.map { e in d.day < e } ?? true) }.sorted { $0.day < $1.day }
            return Period(startLab: b.startLab, start: b.start, endLab: b.end, checked: inside.count, counts: counts, doses: ds)
        }
        return Array(out.reversed().prefix(maxPeriods))
    }

    /// One plain line for a period with checks but nothing ticked often.
    public static func quietLine(_ p: Period) -> String? {
        guard p.checked > 0 else { return "No weekly checks in this stretch." }
        if p.counts.isEmpty { return "Nothing ticked. Near your usual." }
        let ticked = Set(p.counts.filter { $0.weeks > 0 }.map(\.symptom)).count
        return ticked > 0 && p.counts.allSatisfy({ $0.weeks * 2 < p.checked }) ? "Mostly near your usual otherwise." : nil
    }
}
