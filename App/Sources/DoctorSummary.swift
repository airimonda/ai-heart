import AiHeartCore
import SwiftUI

/// A one-page PDF for her doctor: dose changes, labs, weekly balance, doses taken and how
/// often each symptom came up. No journal text, no photos, nothing she wrote about her day.
enum DoctorSummary {
    @MainActor
    static func makePDF(model: BodyBalanceModel, doses: [DoseChange], labs: [LabResult], logs: [MedicationLog], checks: [BodyCheck]) -> URL? {
        let page = SummaryPage(model: model, doses: doses, labs: labs, logs: logs, checks: checks)
            .frame(width: 595)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(width: 595, height: nil)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Summary for my doctor \(Date.now.formatted(.iso8601.year().month().day())).pdf")
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: CGSize(width: 595, height: max(size.height, 842)))
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            pdf.translateBy(x: 0, y: box.height - size.height)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        guard ok else { return nil }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        return url
    }
}

private struct SummaryPage: View {
    let model: BodyBalanceModel
    let doses: [DoseChange]
    let labs: [LabResult]
    let logs: [MedicationLog]
    let checks: [BodyCheck]

    private var betweenTests: [BetweenTests.Period] {
        let cs = checks.compactMap { c in AnchoredDay(key: c.weekKey).map { BetweenTests.Check(week: $0, symptoms: c.signs) } }
        let labDays = Set(labs.map { DayAnchor.day(for: $0.date, timeZone: .current, dayStartHour: 4) }).sorted()
        let ds = doses.map { (day: DayAnchor.day(for: $0.date, timeZone: .current, dayStartHour: 4), text: "\($0.fromText) to \($0.toText)") }
        return BetweenTests.periods(checks: cs, labDays: labDays, doses: ds, today: model.snap.today)
    }

    private func betweenTitle(_ p: BetweenTests.Period) -> String {
        func d(_ a: AnchoredDay) -> String { a.date(in: .current).formatted(.dateTime.day().month(.abbreviated).year()) }
        switch (p.startLab, p.endLab) {
        case (let s?, nil): return "Since \(d(s)) lab"
        case (let s?, let e?): return "\(d(s)) to \(d(e))"
        case (nil, let e?): return "Before \(d(e)) lab"
        case (nil, nil): return "Weekly checks"
        }
    }

    private var symptomCounts: [(String, Int)] {
        let recent = checks.filter { c in model.weeks.contains { $0.start.key == c.weekKey } }
        var counts: [String: Int] = [:]
        for c in recent { for (k, v) in c.signs where v > 0 { counts[k, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }
    }

    private var dosesLast28: Int {
        let cal = Calendar.current
        return Set(logs.filter { $0.takenAt > Date().addingTimeInterval(-28 * 86400) }.map { cal.startOfDay(for: $0.takenAt) }).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Summary for my doctor").font(.system(size: 22, weight: .bold))
                Text("Last 12 weeks, to \(Date.now.formatted(date: .long, time: .omitted)). From my own records in AiHeart.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            section("Lab results, all on record") {
                if labs.isEmpty { line("None recorded.") }
                ForEach(LabReport.group(labs)) { report in
                    line("\(report.date.formatted(date: .abbreviated, time: .omitted)): " + LabText.detail(report))
                }
            }
            section("Dose changes") {
                if doses.isEmpty { line("None recorded.") }
                ForEach(Array(doses.enumerated()), id: \.offset) { _, d in
                    line("\(d.date.formatted(date: .abbreviated, time: .omitted)): \(d.fromText) to \(d.toText)")
                }
            }
            section("Between lab tests: what I ticked in my weekly check (not lab values)") {
                if betweenTests.isEmpty { line("No weekly checks yet.") }
                ForEach(betweenTests) { p in
                    line(betweenTitle(p) + ": " + (p.counts.isEmpty ? (BetweenTests.quietLine(p) ?? "")
                        : p.counts.prefix(5).map { "\($0.symptom) \($0.weeks) of \(p.checked) weeks" }.joined(separator: ", "))
                        + p.doses.map { "; dose changed \($0.day.date(in: .current).formatted(.dateTime.day().month(.abbreviated))) (\($0.text))" }.joined())
                }
            }
            section("Doses logged") {
                line("\(dosesLast28) of the last 28 days.")
            }
            Text("This describes; it does not diagnose. Only the lab results are measurements; the weekly section is what I noticed between tests, and mood and body symptoms can look alike.")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(36)
        .foregroundStyle(.black)
        .background(.white)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content()
        }
    }

    private func line(_ s: String) -> some View { Text(s).font(.system(size: 10)) }
}
