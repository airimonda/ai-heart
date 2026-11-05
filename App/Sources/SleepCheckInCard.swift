import AiHeartCore
import SwiftData
import SwiftUI
import UIKit

/// Morning check-in for nights without a watch (owner, 2026-11-01): bedtime, wake time and
/// how rested she feels. Shown until she answers or skips; prefilled from her usual times,
/// or from the iPhone's sleep schedule when Health has it. Her answer feeds the same sleep
/// baseline, lean and patterns as watch data.
struct SleepCheckInCard: View {
    @Environment(\.modelContext) private var context
    @Query private var summaries: [DaySummary]
    @Query private var settingsRows: [AppSettings]
    @State private var bed = Date()
    @State private var wake = Date()
    @State private var rested: Int?
    @State private var prepared = false
    @State private var editing = false
    /// Set when shown as a sheet from Today's log: opens straight into the questions.
    var asSheet = false
    var onDone: (() -> Void)? = nil

    private var dayStart: Int { settingsRows.first?.dayStartHour ?? 4 }
    private var today: AnchoredDay { DayAnchor.day(for: .now, timeZone: .current, dayStartHour: dayStart) }
    private var row: DaySummary? { summaries.first { $0.dayKey == today.key && $0.deviceId != DemoData.tag } }
    private static func skipKey(_ d: AnchoredDay) -> String { "sleepCheckIn.skipped.\(d.key)" }

    /// Shown when there is no real sleep for today yet, and she has not skipped it.
    static func isDue(_ summaries: [DaySummary], today: AnchoredDay) -> Bool {
        guard !UserDefaults.standard.bool(forKey: skipKey(today)) else { return false }
        let r = summaries.first { $0.dayKey == today.key && $0.deviceId != DemoData.tag }
        guard let r, r.sleepMin != nil else { return true }
        return r.sleepSourceRaw == "inBed" && r.rested == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !asSheet, let r = row, r.sleepSourceRaw == "manual", !editing {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last night").font(.headline).foregroundStyle(Palette.ink)
                        Text(summaryLine(r)).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button("Edit") { load(); editing = true }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minWidth: 44, minHeight: 44)
                }
            } else {
                Text("How did you sleep?").font(.headline).foregroundStyle(Palette.ink)
                if row?.sleepSourceRaw == "inBed" {
                    Text("From your iPhone's sleep schedule. Adjust if it was different.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                HStack {
                    DatePicker("Went to bed", selection: $bed, displayedComponents: .hourAndMinute)
                }
                HStack {
                    DatePicker("Woke up", selection: $wake, displayedComponents: .hourAndMinute)
                }
                Text("\(BodyFormat.duration(minutes)) of sleep").font(.subheadline).foregroundStyle(Palette.muted)
                Text("How rested do you feel?").font(.subheadline).foregroundStyle(Palette.ink)
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { n in
                        Button { rested = rested == n ? nil : n } label: {
                            Text("\(n)")
                                .font(.headline)
                                .foregroundStyle(rested == n ? Palette.onAction : Palette.ink)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(rested == n ? Palette.action : Palette.segment, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(n) of 5")
                        .accessibilityAddTraits(rested == n ? .isSelected : [])
                    }
                }
                HStack { Text("Not at all"); Spacer(); Text("Fully") }.font(.caption).foregroundStyle(Palette.muted)
                HStack {
                    Button("Not today") {
                        UserDefaults.standard.set(true, forKey: Self.skipKey(today))
                        editing = false
                        onDone?()
                    }
                    .font(.subheadline).foregroundStyle(Palette.muted).frame(minHeight: 44)
                    Spacer()
                    Button("Save", action: save)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .onAppear { if !prepared { load(); prepared = true } }
    }

    private var minutes: Double { SleepCheckIn.minutes(bed: bed, wake: wake) }

    private func summaryLine(_ r: DaySummary) -> String {
        var parts: [String] = []
        if let b = r.bedtime, let w = r.wakeTime {
            parts.append("\(b.formatted(date: .omitted, time: .shortened))–\(w.formatted(date: .omitted, time: .shortened))")
        }
        if let m = r.sleepMin { parts.append(BodyFormat.duration(m)) }
        if let x = r.rested { parts.append("rested \(x) of 5") }
        return parts.joined(separator: " · ")
    }

    /// Prefill: her saved answer, else the sleep schedule's times, else her usual check-in times.
    private func load() {
        let cal = Calendar.current
        func minuteOfDay(_ d: Date) -> Int { cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d) }
        let manual = summaries.filter { $0.sleepSourceRaw == "manual" && $0.deviceId != DemoData.tag }
        let usual = SleepCheckIn.usual(bedMinutes: manual.compactMap(\.bedtime).map(minuteOfDay),
                                       wakeMinutes: manual.compactMap(\.wakeTime).map(minuteOfDay))
        let d = SleepCheckIn.dates(wakeDay: today, bedMinute: usual.bed, wakeMinute: usual.wake, timeZone: .current)
        bed = row?.bedtime ?? d.bed
        wake = row?.wakeTime ?? d.wake
        if row?.sleepSourceRaw == "inBed", let m = row?.sleepMin {
            bed = wake.addingTimeInterval(-m * 60)
        }
        rested = row?.rested
    }

    private func save() {
        let s = row ?? {
            let n = DaySummary(day: today, timeZone: .current)
            n.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
            context.insert(n)
            return n
        }()
        // Store the night as dates ending on today's wake time.
        let cal = Calendar.current
        let w = SleepCheckIn.dates(wakeDay: today,
                                   bedMinute: cal.component(.hour, from: bed) * 60 + cal.component(.minute, from: bed),
                                   wakeMinute: cal.component(.hour, from: wake) * 60 + cal.component(.minute, from: wake),
                                   timeZone: .current)
        s.bedtime = w.bed
        s.wakeTime = w.wake
        s.sleepMin = SleepCheckIn.minutes(bed: w.bed, wake: w.wake)
        s.sleepSourceRaw = "manual"
        s.rested = rested
        s.updatedAt = .now
        try? context.save()
        editing = false
        onDone?()
    }
}
