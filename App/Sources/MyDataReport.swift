import AiHeartCore
import Charts
import SwiftData
import SwiftUI

/// "My data" (M11, owner 2026-11-01): her numbers as charts and tables, not raw files.
/// Built on the phone; goes only where she sends it. No journal text unless she asks.
@MainActor
enum MyDataPDF {
    struct Options {
        var from: AnchoredDay
        var to: AnchoredDay
        var includeWriting: Bool
        var includeLabs: Bool
    }

    static func make(summaries: [DaySummary], entries: [Entry], workouts: [Workout], labs: [LabResult], doses: [DoseChange],
                     checks: [BodyCheck], dayStart: Int, demo: Bool, options o: Options) -> URL? {
        let cal = Calendar.current
        func inRange(_ d: AnchoredDay) -> Bool { d >= o.from && d <= o.to }
        let real = { (id: String) in demo || id != DemoData.tag }

        // One row per day with anything in it.
        var rows: [AnchoredDay: MonthlyTable.DayRow] = [:]
        for s in summaries where real(s.deviceId) {
            guard let d = s.day, inRange(d) else { continue }
            var r = rows[d] ?? .init(day: d)
            r.sleepH = s.sleepMin.map { $0 / 60 }; r.restingHR = s.restingHR; r.hrv = s.hrvSDNN; r.steps = s.steps
            rows[d] = r
        }
        var moodSum: [AnchoredDay: (Double, Int)] = [:]
        for e in entries where e.status != .released && real(e.deviceId) {
            guard let v = e.valence else { continue }
            let d = DayAnchor.day(for: e.createdAt, timeZone: e.timeZone, dayStartHour: dayStart)
            guard inRange(d) else { continue }
            let m = moodSum[d] ?? (0, 0); moodSum[d] = (m.0 + v, m.1 + 1)
        }
        for (d, m) in moodSum { var r = rows[d] ?? .init(day: d); r.mood = m.0 / Double(m.1); rows[d] = r }
        for w in workouts where real(w.deviceId) {
            let d = DayAnchor.day(for: w.start, timeZone: .current, dayStartHour: dayStart)
            guard inRange(d) else { continue }
            var r = rows[d] ?? .init(day: d); r.workouts += 1; r.workoutMin += Double(w.minutes); rows[d] = r
        }
        let dayRows = rows.values.sorted { $0.day < $1.day }
        let months = MonthlyTable.months(dayRows)
        let weeks = MonthlyTable.weeks(dayRows, weekStart: BodyBalanceModel.monday)

        var blocks: [AnyView] = []
        let fromDate = o.from.date(in: cal), toDate = o.to.date(in: cal)
        blocks.append(AnyView(VStack(alignment: .leading, spacing: 4) {
            Text("My data").font(.system(size: 22, weight: .bold))
            Text("\(fromDate.formatted(date: .long, time: .omitted)) to \(toDate.formatted(date: .long, time: .omitted))").font(.system(size: 11))
            Text("From my own records in AiHeart. Averages skip days with no reading; (n) is the number of days behind each number. It describes; it does not diagnose.")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }.foregroundStyle(.black)))

        // Monthly table.
        blocks.append(TherapistPDF.heading("Month by month"))
        blocks.append(AnyView(MonthTable(rows: months)))

        // Charts.
        if weeks.contains(where: { $0.mood != nil }) {
            blocks.append(TherapistPDF.heading("Mood, weekly average"))
            blocks.append(AnyView(WeekLine(rows: weeks, value: { $0.mood?.value }, domain: -1...1,
                                           yLabels: [(-1, "unpleasant"), (0, "middle"), (1, "pleasant")])))
        }
        if weeks.contains(where: { $0.sleepH != nil }) {
            blocks.append(TherapistPDF.heading("Sleep, weekly average (hours)"))
            blocks.append(AnyView(WeekLine(rows: weeks, value: { $0.sleepH?.value }, domain: nil, yLabels: [])))
        }
        if weeks.contains(where: { $0.restingHR != nil }) {
            blocks.append(TherapistPDF.heading("Resting heart rate, weekly average (bpm)"))
            blocks.append(AnyView(WeekLine(rows: weeks, value: { $0.restingHR?.value }, domain: nil, yLabels: [])))
        }
        if weeks.contains(where: { $0.workouts > 0 }) {
            blocks.append(TherapistPDF.heading("Workouts per week"))
            blocks.append(AnyView(WeekBars(rows: weeks)))
        }

        if o.includeLabs {
            let ls = labs.filter { real($0.deviceId) }.sorted { $0.date < $1.date }
            if !ls.isEmpty {
                blocks.append(TherapistPDF.heading("Lab results"))
                for m in LabMarkers.all where ls.contains(where: { $0.marker == m.code && $0.value != nil }) {
                    blocks.append(AnyView(LabChart(marker: m, labs: ls, doses: doses.filter { real($0.deviceId) })))
                }
                blocks.append(AnyView(LabTable(labs: ls)))
            }
            let cs = checks.filter { real($0.deviceId) }.compactMap { c in
                AnchoredDay(key: c.weekKey).map { BetweenTests.Check(week: $0, symptoms: c.signs) }
            }
            let periods = BetweenTests.periods(checks: cs, labDays: Set(ls.map { DayAnchor.day(for: $0.date, timeZone: .current, dayStartHour: dayStart) }).sorted(),
                                               doses: doses.map { (DayAnchor.day(for: $0.date, timeZone: .current, dayStartHour: dayStart), "\($0.fromText) to \($0.toText)") },
                                               today: o.to, maxPeriods: 6)
            if !periods.isEmpty {
                blocks.append(TherapistPDF.heading("Between tests: what I ticked in my weekly check"))
                blocks.append(AnyView(BetweenTable(periods: periods)))
            }
        }

        if o.includeWriting {
            let written = entries.filter { $0.status == .kept && real($0.deviceId) && !($0.text ?? "").isEmpty }
                .filter { inRange(DayAnchor.day(for: $0.createdAt, timeZone: $0.timeZone, dayStartHour: dayStart)) }
            if !written.isEmpty {
                blocks.append(TherapistPDF.heading("My writing"))
                for e in written {
                    blocks.append(AnyView(VStack(alignment: .leading, spacing: 2) {
                        Text(e.createdAt.formatted(date: .abbreviated, time: .shortened) + (e.word.map { " · " + $0 } ?? ""))
                            .font(.system(size: 9, weight: .semibold))
                        Text(e.text ?? "").font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
                    }.foregroundStyle(.black)))
                }
            }
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("My data \(toDate.formatted(.iso8601.year().month().day())).pdf")
        return PDFPager.write(blocks: blocks, to: url) ? url : nil
    }
}

// MARK: Report pieces (black on white, small type)

private func fmt(_ m: MonthlyTable.Mean?, _ digits: Int = 1) -> String {
    guard let m else { return "–" }
    return m.value.formatted(.number.precision(.fractionLength(digits)).grouping(.never)) + " (\(m.days))"
}

private struct MonthTable: View {
    let rows: [MonthlyTable.Row]
    var body: some View {
        let cols = ["Month", "Sleep h", "Resting HR", "HRV ms", "Steps", "Mood", "Workouts"]
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(cols, id: \.self) { Text($0).bold().frame(maxWidth: .infinity, alignment: .leading) } }
                .padding(.vertical, 4).background(Color(white: 0.92))
            ForEach(rows) { r in
                HStack(spacing: 0) {
                    Text(r.start.date(in: .current).formatted(.dateTime.month(.abbreviated).year(.twoDigits))).frame(maxWidth: .infinity, alignment: .leading)
                    Text(fmt(r.sleepH)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(fmt(r.restingHR, 0)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(fmt(r.hrv, 0)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(r.steps.map { "\(Int($0.value.rounded()).formatted())" } ?? "–").frame(maxWidth: .infinity, alignment: .leading)
                    Text(fmt(r.mood, 2)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(r.workouts == 0 ? "–" : "\(r.workouts) · \(Int(r.workoutMin)) min").frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 3)
                Divider()
            }
            Text("Mood is the average mood point, from −1 (unpleasant) to +1 (pleasant).").font(.system(size: 8)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 3)
        }
        .font(.system(size: 8.5)).foregroundStyle(.black)
    }
}

private struct WeekLine: View {
    let rows: [MonthlyTable.Row]
    let value: (MonthlyTable.Row) -> Double?
    let domain: ClosedRange<Double>?
    let yLabels: [(Double, String)]
    var body: some View {
        let pts = rows.compactMap { r in value(r).map { (r.start.date(in: .current), $0) } }
        Chart {
            ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Week", p.0), y: .value("Value", p.1)).foregroundStyle(Color(red: 0.71, green: 0.27, blue: 0.44))
                PointMark(x: .value("Week", p.0), y: .value("Value", p.1)).symbolSize(12).foregroundStyle(Color(red: 0.71, green: 0.27, blue: 0.44))
            }
        }
        .chartYScale(domain: domain ?? autoDomain(pts.map(\.1)))
        .chartYAxis {
            if yLabels.isEmpty { AxisMarks(position: .leading) }
            else { AxisMarks(position: .leading, values: yLabels.map(\.0)) { v in
                AxisGridLine()
                AxisValueLabel { Text(yLabels.first { $0.0 == v.as(Double.self) }?.1 ?? "") }
            } }
        }
        .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
        .frame(height: 120)
        .font(.system(size: 8))
    }

    private func autoDomain(_ v: [Double]) -> ClosedRange<Double> {
        guard let lo = v.min(), let hi = v.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.15, 0.5)
        return (lo - pad)...(hi + pad)
    }
}

private struct WeekBars: View {
    let rows: [MonthlyTable.Row]
    var body: some View {
        Chart {
            ForEach(rows) { r in
                BarMark(x: .value("Week", r.start.date(in: .current), unit: .weekOfYear), y: .value("Workouts", r.workouts))
                    .foregroundStyle(Color(red: 0.93, green: 0.55, blue: 0.70))
            }
        }
        .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
        .frame(height: 100)
        .font(.system(size: 8))
    }
}

private struct LabChart: View {
    let marker: LabMarker
    let labs: [LabResult]
    let doses: [DoseChange]
    var body: some View {
        let mine = labs.filter { $0.marker == marker.code && $0.value != nil }
        let pts = mine.compactMap { l in l.value.map { (l.date, $0) } }
        let unit = mine.last?.unit ?? ""
        let range = mine.last?.shownRange
        VStack(alignment: .leading, spacing: 2) {
            Text("\(marker.name) (\(unit))").font(.system(size: 9, weight: .semibold))
            Chart {
                if let range {
                    RectangleMark(yStart: .value("Low", range.low), yEnd: .value("High", range.high))
                        .foregroundStyle(Color(white: 0.93))
                }
                ForEach(doses, id: \.syncId) { d in
                    RuleMark(x: .value("Dose", d.date)).foregroundStyle(.gray).lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                }
                ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Date", p.0), y: .value(marker.name, p.1)).foregroundStyle(Color(red: 0.71, green: 0.27, blue: 0.44))
                    PointMark(x: .value("Date", p.0), y: .value(marker.name, p.1)).foregroundStyle(Color(red: 0.71, green: 0.27, blue: 0.44))
                        .annotation(position: .top) { Text(p.1.formatted(.number.precision(.fractionLength(0...2)))).font(.system(size: 7)) }
                }
            }
            .frame(height: 90)
            .font(.system(size: 8))
            Text(range.map { "Grey band: \($0.fromLab ? "the lab's range" : "typical range"). Dashed lines: dose changes." } ?? "Dashed lines: dose changes.")
                .font(.system(size: 7.5)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.black)
    }
}

private struct LabTable: View {
    let labs: [LabResult]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Date").bold().frame(width: 80, alignment: .leading)
                Text("Results").bold().frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4).background(Color(white: 0.92))
            ForEach(LabReport.group(labs)) { report in
                HStack(alignment: .top, spacing: 0) {
                    Text(report.date.formatted(date: .abbreviated, time: .omitted)).frame(width: 80, alignment: .leading)
                    Text(LabText.detail(report)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 3)
                Divider()
            }
        }
        .font(.system(size: 8.5)).foregroundStyle(.black)
    }
}

private struct BetweenTable: View {
    let periods: [BetweenTests.Period]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(periods.filter { $0.checked > 0 }) { p in
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(p)).font(.system(size: 9, weight: .semibold))
                    if p.counts.isEmpty {
                        Text(BetweenTests.quietLine(p) ?? "").font(.system(size: 8.5))
                    } else {
                        Text(p.counts.prefix(6).map { "\($0.symptom) \($0.weeks) of \(p.checked)" }.joined(separator: " · ")).font(.system(size: 8.5))
                    }
                    ForEach(Array(p.doses.enumerated()), id: \.offset) { _, d in
                        Text("Dose changed \(d.day.date(in: .current).formatted(date: .abbreviated, time: .omitted)): \(d.text)").font(.system(size: 8.5))
                    }
                }
            }
        }
        .foregroundStyle(.black)
    }

    private func title(_ p: BetweenTests.Period) -> String {
        func d(_ a: AnchoredDay) -> String { a.date(in: .current).formatted(date: .abbreviated, time: .omitted) }
        let n = p.checked == 1 ? "1 weekly check" : "\(p.checked) weekly checks"
        switch (p.startLab, p.endLab) {
        case (let s?, nil): return "Since the \(d(s)) lab (\(n))"
        case (let s?, let e?): return "\(d(s)) to \(d(e)) (\(n))"
        case (nil, let e?): return "Before the \(d(e)) lab (\(n))"
        case (nil, nil): return "Weekly checks (\(n))"
        }
    }
}
