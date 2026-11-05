import AiHeartCore
import SwiftData
import SwiftUI

/// Synthetic sample data for demos. Every row is tagged with `deviceId == "demo"` so it can
/// be removed cleanly. Never the owner's real data, and never mixed with Apple Health:
/// Health sync pauses while sample data is on.
enum DemoData {
    static let tag = "demo"

    @MainActor static func isOn(_ context: ModelContext) -> Bool {
        let tag = Self.tag
        let d = FetchDescriptor<DaySummary>(predicate: #Predicate { $0.deviceId == tag })
        return ((try? context.fetchCount(d)) ?? 0) > 0
    }

    /// The sample "last 7 days" vibe, so the Media card and Now line show without the model.
    @MainActor static func sampleVibe(today: AnchoredDay) {
        let vibe = MediaVibe(tags: ["dreamy", "warm", "nostalgic"], valence: 0.45, energy: -0.1,
                             line: "Soft indie and acoustic songs about home and slow mornings, with one bright synth track and cozy cooking shows.",
                             weekKey: today.key)
        if let d = try? JSONEncoder().encode(vibe) { UserDefaults.standard.set(d, forKey: "media.vibe2.latest") }
        MediaVibeStore.shared.load()
    }

    @MainActor static func remove(_ context: ModelContext) {
        let tag = Self.tag
        try? context.delete(model: DaySummary.self, where: #Predicate { $0.deviceId == tag })
        try? context.delete(model: Entry.self, where: #Predicate { $0.deviceId == tag })
        try? context.delete(model: Workout.self, where: #Predicate { $0.deviceId == tag })
        try? context.delete(model: BodyCheck.self, where: #Predicate { $0.deviceId == tag })
        try? context.delete(model: LabResult.self, where: #Predicate { $0.deviceId == tag })
        try? context.delete(model: DoseChange.self, where: #Predicate { $0.deviceId == tag })
        try? context.delete(model: MedicationLog.self, where: #Predicate { $0.deviceId == tag })
        try? context.delete(model: HevySet.self, where: #Predicate { $0.hevyWorkoutId.starts(with: "demo-") })
        try? context.delete(model: MediaItem.self, where: #Predicate { $0.deviceId == tag })
        try? context.delete(model: AppOpen.self, where: #Predicate { $0.deviceId == tag })
        try? context.save()
    }

    /// Deterministic generator so the demo looks the same each time.
    struct RNG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func normal(_ mean: Double, _ sd: Double) -> Double {
            let u = max(next(), 1e-9), v = next()
            return mean + sd * sqrt(-2 * log(u)) * cos(2 * .pi * v)
        }
    }

    @MainActor static func fill(_ context: ModelContext, dayStartHour: Int = 4) {
        remove(context)
        var rng = RNG(state: 2026)
        let tz = TimeZone.current
        let today = DayAnchor.day(for: .now, timeZone: tz, dayStartHour: dayStartHour)

        // 120 days of body signals over four 28-day cycles, with today on cycle day 22.
        // After ovulation (cycle day 15) resting HR rises, HRV falls and wrist temperature
        // steps up. A few short nights and some missing days, left blank.
        let starts = [-105, -77, -49, -21]
        var sleepByDay: [AnchoredDay: Double] = [:]
        func cycleDay(_ back: Int) -> Int? {
            starts.last(where: { $0 <= -back }).map { -back - $0 + 1 }
        }
        for back in stride(from: 119, through: 0, by: -1) {
            let day = today.adding(days: -back)
            if back > 0 && rng.next() < 0.06 { continue } // missing day: left blank, not imputed
            let cd = cycleDay(back) ?? (back - 105 + 14)
            let luteal = cd >= 16 ? 1.0 : 0.0
            let s = DaySummary(day: day, timeZone: tz)
            s.deviceId = tag
            if cd >= 1 && cd <= 5 { s.menstrualFlow = [3, 4, 3, 2, 2][cd - 1] }
            var sleep = rng.normal(432, 30)
            if rng.next() < 0.12 { sleep -= 70 }
            s.sleepMin = sleep
            sleepByDay[day] = sleep
            s.sleepDeepMin = sleep * rng.normal(0.16, 0.02)
            s.sleepRemMin = sleep * rng.normal(0.22, 0.03)
            s.sleepCoreMin = sleep - (s.sleepDeepMin ?? 0) - (s.sleepRemMin ?? 0)
            s.awakeMin = rng.normal(22, 8)
            s.restingHR = rng.normal(58 + 2.5 * luteal, 1.2)
            s.hrvSDNN = rng.normal(50 - 5 * luteal, 3.5)
            s.respRate = rng.normal(14.2 + 0.3 * luteal, 0.3)
            s.wristTempC = rng.normal(35.9 + 0.35 * luteal, 0.05)
            let active = rng.next() < 0.4
            s.steps = rng.normal(active ? 9200 : 5600, 1400)
            s.activeKcal = rng.normal(active ? 420 : 210, 50)
            s.basalKcal = rng.normal(1420, 20)
            s.exerciseMin = rng.normal(active ? 48 : 14, 8)
            if back == 0 {
                // Today: a short night and a more stirred body, so the suggestions change.
                s.sleepMin = 368; s.restingHR = 63; s.hrvSDNN = 39; s.wristTempC = 36.27
                s.steps = 3100; s.activeKcal = 140; s.exerciseMin = 9
            }
            context.insert(s)
        }

        // About 80 journal entries over 100 days. Mood is a little lower in the last days
        // of each cycle, so the mood-across-cycle chart has something to show.
        let words = ["Calm", "Tired", "Bright", "Tense", "Content", "Wired", "Okay", "Heavy", "Restless", "Flat", "Excited"]
        let lines = [
            "[Sample] Coffee by the window before anyone was up.",
            "[Sample] Long walk after work. The light was soft.",
            "[Sample] Hard to focus this afternoon.",
            "[Sample] Lifted. Felt strong on the last set.",
            "[Sample] Quiet.",
            "[Sample] Read on the train. Did not check my phone.",
            "[Sample] Practised Japanese for twenty minutes.",
            "[Sample] Slow evening. Early night.",
        ]
        let regionSets: [[String]] = [["chest"], ["throat", "chest"], ["shoulders", "neckBack"], ["stomach"], ["head"], ["lowerBack"]]
        let sensationSets: [[String]] = [["Tight"], ["Heavy"], ["Buzzing", "Warm"], ["Knotted"], ["Light", "Soft"], ["Achy"]]
        let palettes: [(UInt32, UInt32)] = [(0xFCE4ED, 0xE6D6F0), (0xF6CADB, 0xFDF1F6), (0xFDE8DF, 0xF6CADB), (0xEEE3F4, 0xFCE4ED)]

        var cal = Calendar.current
        cal.timeZone = tz
        for back in stride(from: 99, through: 0, by: -1) {
            if rng.next() < 0.22 && back != 0 { continue }
            let dayDate = today.adding(days: -back).date(in: cal)
            let hour = [8, 12, 18, 21][Int(rng.next() * 4) % 4]
            let at = cal.date(bySettingHour: hour, minute: Int(rng.next() * 50), second: 0, of: dayDate) ?? dayDate
            let lateCycle = (cycleDay(back) ?? 0) >= 24
            let pool = lateCycle ? ["Tired", "Tense", "Heavy", "Flat", "Restless", "Okay"] : words
            let word = pool[Int(rng.next() * Double(pool.count)) % pool.count]
            let p = MoodWords.point(for: word) ?? .center
            let roll = rng.next()
            let kind: EntryKind = roll < 0.3 ? .photo : roll < 0.5 ? .write : roll < 0.65 ? .body : .feeling
            let e = Entry(kind: kind, createdAt: at, timeZone: tz)
            e.deviceId = tag
            e.word = word
            // Synthetic links so the Patterns charts have something to show: a little more
            // pleasant after longer nights and on lift days (Mon, Wed, Fri).
            let dayKey = today.adding(days: -back)
            let sleepNudge = ((sleepByDay[dayKey] ?? 432) - 432) / 30 * 0.12
            let liftNudge = [2, 4, 6].contains(cal.component(.weekday, from: dayDate)) ? 0.12 : 0
            e.valence = MoodPoint(valence: p.valence + sleepNudge + liftNudge + rng.normal(0, 0.08), arousal: 0).valence
            e.arousal = MoodPoint(valence: 0, arousal: p.arousal + rng.normal(0, 0.08)).arousal
            if kind == .photo || kind == .write {
                e.text = lines[Int(rng.next() * Double(lines.count)) % lines.count]
            }
            if kind == .photo {
                let c = palettes[Int(rng.next() * Double(palettes.count)) % palettes.count]
                if let img = gradient(UIColor(hex: c.0), UIColor(hex: c.1)) { e.photoData = img.photo; e.thumbData = img.thumb }
            }
            if kind == .body || rng.next() < 0.25 {
                let i = Int(rng.next() * Double(regionSets.count)) % regionSets.count
                e.bodyRegions = regionSets[i]
                e.sensations = sensationSets[i]
            }
            context.insert(e)
        }

        // Workouts: lifts from Health and Hevy (merged), walks and a run from Health.
        // Most are rated; today's lift is not, so "Rate" shows on Insights.
        let exercises = [("Squat", 70.0), ("Bench Press", 40.0), ("Romanian Deadlift", 60.0), ("Row", 42.5), ("Overhead Press", 27.5)]
        for back in stride(from: 59, through: 0, by: -1) {
            let dayDate = today.adding(days: -back).date(in: cal)
            let weekday = cal.component(.weekday, from: dayDate)
            let isLift = [2, 4, 6].contains(weekday) || back == 0
            let isWalk = !isLift && rng.next() < 0.5
            let isRun = !isLift && !isWalk && rng.next() < 0.25
            guard isLift || isWalk || isRun else { continue }
            let start = cal.date(bySettingHour: isLift ? 7 : 18, minute: 10, second: 0, of: dayDate) ?? dayDate
            if back == 0 && start > .now { continue }
            let kind: WorkoutKind = isLift ? .strength : isWalk ? .walk : .run
            let minutes = isLift ? rng.normal(52, 6) : isWalk ? rng.normal(38, 8) : rng.normal(30, 5)
            let w = Workout(kind: kind, start: start, durationSec: minutes * 60)
            w.deviceId = tag
            w.healthId = "demo-h-\(back)"
            w.activeKcal = minutes * (isLift ? 6 : isWalk ? 4 : 10)
            w.avgHR = isLift ? rng.normal(118, 6) : isWalk ? rng.normal(102, 5) : rng.normal(148, 6)
            if isLift {
                let id = "demo-\(back)"
                w.hevyId = id
                w.title = ["Upper", "Lower", "Full body"][back % 3]
                w.focus = [.upper, .lower, .fullBody][back % 3]
                for (ei, ex) in exercises.enumerated() where (back + ei) % 2 == 0 || ei == 0 {
                    for si in 0..<3 {
                        let set = HevySet(hevyWorkoutId: id, exerciseIndex: ei, exerciseName: ex.0, setIndex: si)
                        set.weightKg = ex.1 + Double(60 - back) * 0.1
                        set.reps = [8, 8, 6][si]
                        context.insert(set)
                    }
                }
            }
            if back > 0 && rng.next() < 0.85 {
                w.rpe = Int(rng.normal(isLift ? 7 : 4, 1).rounded()).clamped(1, 10)
                w.ratedAt = start.addingTimeInterval(minutes * 60 + 1800)
            }
            w.promptedAt = back == 0 ? nil : w.ratedAt
            context.insert(w)
        }

        // Labs and body check: a dose change six weeks ago, lab reports before and after, weekly
        // checks that lean to the lower side before the change and a little to the higher side
        // after it, and a daily dose log around 06:30 with one gap.
        let thisMonday = BodyBalanceModel.monday(today)
        let doseDay = thisMonday.adding(days: -42).date(in: cal)
        let dc = DoseChange(date: doseDay, from: "5 mg", to: "10 mg"); dc.deviceId = tag; context.insert(dc)
        // A report roughly every six months over two years, plus one after the dose change.
        // Sample values only: marker code, value, unit, the lab's range.
        typealias Sample = (code: String, value: Double, unit: String, low: Double, high: Double)
        let reports: [(daysBack: Int, results: [Sample])] = [
            (730, [("GLU", 86, "mg/dL", 70, 99), ("A1C", 5.2, "%", 4.0, 5.6), ("LDL", 108, "mg/dL", 0, 130), ("HDL", 58, "mg/dL", 40, 100),
                   ("HGB", 13.2, "g/dL", 12.0, 15.5), ("FER", 44, "ng/mL", 10, 120), ("VITD", 31, "ng/mL", 30, 100)]),
            (550, [("GLU", 90, "mg/dL", 70, 99), ("A1C", 5.3, "%", 4.0, 5.6), ("LDL", 112, "mg/dL", 0, 130), ("HDL", 56, "mg/dL", 40, 100),
                   ("HGB", 12.9, "g/dL", 12.0, 15.5), ("FER", 38, "ng/mL", 10, 120), ("VITD", 27, "ng/mL", 30, 100)]),
            (370, [("GLU", 92, "mg/dL", 70, 99), ("A1C", 5.4, "%", 4.0, 5.6), ("LDL", 118, "mg/dL", 0, 130), ("HDL", 55, "mg/dL", 40, 100),
                   ("HGB", 12.6, "g/dL", 12.0, 15.5), ("FER", 31, "ng/mL", 10, 120), ("CRE", 0.74, "mg/dL", 0.5, 1.0)]),
            (190, [("GLU", 95, "mg/dL", 70, 99), ("A1C", 5.5, "%", 4.0, 5.6), ("LDL", 121, "mg/dL", 0, 130), ("HDL", 54, "mg/dL", 40, 100),
                   ("HGB", 12.4, "g/dL", 12.0, 15.5), ("FER", 27, "ng/mL", 10, 120), ("CRE", 0.76, "mg/dL", 0.5, 1.0)]),
            (60, [("GLU", 97, "mg/dL", 70, 99), ("A1C", 5.5, "%", 4.0, 5.6), ("LDL", 126, "mg/dL", 0, 130), ("HDL", 53, "mg/dL", 40, 100),
                  ("HGB", 12.2, "g/dL", 12.0, 15.5), ("FER", 22, "ng/mL", 10, 120), ("VITD", 24, "ng/mL", 30, 100)]),
            (10, [("GLU", 88, "mg/dL", 70, 99), ("A1C", 5.3, "%", 4.0, 5.6), ("LDL", 109, "mg/dL", 0, 130), ("HDL", 57, "mg/dL", 40, 100),
                  ("HGB", 13.0, "g/dL", 12.0, 15.5), ("FER", 41, "ng/mL", 10, 120), ("VITD", 33, "ng/mL", 30, 100)]),
        ]
        for report in reports {
            let reportId = UUID()
            let when = thisMonday.adding(days: -report.daysBack).date(in: cal)
            for sample in report.results {
                let l = LabResult(date: when, marker: sample.code)
                l.value = sample.value; l.unit = sample.unit; l.low = sample.low; l.high = sample.high
                l.reportId = reportId; l.deviceId = tag
                context.insert(l)
            }
        }
        for w in 1...11 {
            let week = thisMonday.adding(days: -7 * w)
            let c = BodyCheck(week: week); c.deviceId = tag
            if w > 6 {
                c.signs = ["Tired": 2, "Foggy": 1, "Cold": Int(rng.next() * 2)]
            } else {
                c.signs = ["Tired": Int(rng.next() * 2), "Short sleep": 1, "Racing heart": w < 3 ? 1 : 0, "Shaky": Int(rng.next() * 2)]
            }
            c.signs = c.signs.filter { $0.value > 0 }
            c.tookAsUsual = w == 4 ? .mostly : .yes
            context.insert(c)
        }
        for back in 0..<30 where back != 5 {
            let d = today.adding(days: -back).date(in: cal)
            guard let t = cal.date(bySettingHour: 6, minute: 20 + Int(rng.next() * 25), second: 0, of: d), t <= .now else { continue }
            let l = MedicationLog(takenAt: t); l.deviceId = tag
            if rng.next() < 0.15 { l.with = ["Coffee"] }
            context.insert(l)
        }

        // One resting entry and one let go, to show both cards.
        let resting = Entry(kind: .write, createdAt: cal.date(byAdding: .day, value: -2, to: .now)!, timeZone: tz)
        resting.deviceId = tag
        resting.text = "[Sample] An awful day, we had a fight and I cried. A bath helped. I needed to stop early."
        resting.word = "Heavy"; resting.valence = -0.5; resting.arousal = -0.3
        context.insert(resting)
        try? EntryLifecycle.letGo(resting, restDays: 7, keptLines: ["A bath helped.", "I needed to stop early."], by: .auto)
        resting.releaseNote = ReleaseNotes.fallback(text: resting.text ?? "", keptLines: resting.keptLines)

        let gone = Entry(kind: .write, createdAt: cal.date(byAdding: .day, value: -9, to: .now)!, timeZone: tz)
        gone.deviceId = tag
        gone.status = .released
        gone.decidedBy = .auto
        gone.releasedAt = cal.date(byAdding: .day, value: -2, to: .now)
        gone.keptLines = ["[Sample] Talking to a friend helped."]
        var goneNote = ReleaseNote()
        goneNote.happened = "[Sample] A plan fell through at work."
        goneNote.thought = "I never get anything right."
        goneNote.feelings = [.frustrated, .disappointed]
        goneNote.urge = "I wanted to go home and hide."
        goneNote.intensity = .strong
        goneNote.intensityQuote = "I couldn't stop thinking about it."
        goneNote.needs = [NeedNote(need: .capable, met: false, quote: "I never get anything right."),
                          NeedNote(need: .connection, met: true, quote: "Talking to a friend helped.")]
        goneNote.helped = gone.keptLines
        gone.releaseNote = goneNote
        gone.valence = -0.6; gone.arousal = 0.4
        context.insert(gone)

        // Sample media for the last 7 days (made-up titles), app opens, and a sample vibe.
        let songs: [(String, String, String)] = [
            ("[Sample] Slow Morning", "[Sample] Paper Moons", "indie pop, dream pop"),
            ("[Sample] Rooftop Summer", "[Sample] Paper Moons", "indie pop"),
            ("[Sample] Ulan", "[Sample] Kape't Gitara", "opm, acoustic"),
            ("[Sample] Neon Run", "[Sample] Night Drive", "synthwave"),
            ("[Sample] Letters Home", "[Sample] Quiet Rooms", "folk, acoustic"),
        ]
        for d in 0..<7 {
            for k in 0..<(3 + d % 3) {
                let s = songs[(d + k) % songs.count]
                let start = cal.date(byAdding: .minute, value: -(d * 1440 + 60 * (k + 2) + 30), to: .now)!
                let m = MediaItem(source: .spotify, title: s.0, creator: s.1, startedAt: start, durationSec: 210)
                m.genres = s.2; m.aiEligible = true; m.deviceId = tag
                m.dedupeKey = "demo|\(d)|\(k)"
                context.insert(m)
            }
            if d % 2 == 0 {
                let show = MediaItem(source: .netflix, title: "[Sample] Cozy Kitchen: Episode \(d + 1)", creator: nil,
                                     startedAt: cal.date(byAdding: .minute, value: -(d * 1440 + 180), to: .now)!, durationSec: 2700)
                show.deviceId = tag; show.aiEligible = true; show.dedupeKey = "demo|tv|\(d)"
                context.insert(show)
            }
            for app in ["Instagram", "TikTok"] where d < 6 {
                for n in 0..<(app == "Instagram" ? 4 : 2) {
                    context.insert(AppOpen(appName: app, date: cal.date(byAdding: .minute, value: -(d * 1440 + n * 97 + 20), to: .now)!, deviceId: tag))
                }
            }
        }
        sampleVibe(today: today)

        try? context.save()
    }

    private static func gradient(_ a: UIColor, _ b: UIColor) -> (photo: Data, thumb: Data)? {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [a.cgColor, b.cgColor] as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 800, y: 600), options: [])
        }
        return ImageTools.prepare(img)
    }
}

private extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.min(hi, Swift.max(lo, self)) }
}
