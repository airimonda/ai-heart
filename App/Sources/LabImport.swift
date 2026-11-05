import AiHeartCore
import Charts
import PhotosUI
import SwiftData
import SwiftUI

/// Add or edit the results of one lab report, by hand or from a screenshot. Pick the markers
/// she has; units are picked, never typed. The range shown is the lab's own when known, else
/// the typical adult range for the unit when there is one.
struct AddLabView: View {
    var editing: LabReport?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LabResult.date, order: .reverse) private var allLabs: [LabResult]
    @State private var date = Date()
    @State private var rows: [Row] = []
    @State private var note = ""
    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    @State private var readNote: String?
    @State private var fromScreenshot = false
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var region: LabRegion = .elsewhere
    /// Text rows read from the last screenshot. Shown on this phone only; never saved.
    @State private var readRows: [String] = []

    struct Row: Identifiable {
        let id = UUID()
        var code: String
        var value = ""
        var unit: String
        /// The lab's own range, when the report printed one.
        var labRange: (Double, Double)?
    }

    private var unusedMarkers: [LabMarker] {
        LabMarkers.all.filter { m in !rows.contains { $0.code == m.code } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(reading ? "Reading…" : "Read from a screenshot", systemImage: "doc.text.viewfinder")
                    }
                    .disabled(reading)
                } footer: {
                    Text(readNote ?? "Read on this phone. The screenshot is not kept and nothing is sent anywhere. Check the numbers before saving.")
                }
                if !readRows.isEmpty {
                    Section {
                        DisclosureGroup("What the phone read") {
                            ForEach(Array(readRows.enumerated()), id: \.offset) { _, row in
                                Text(row).font(.caption.monospaced()).foregroundStyle(Palette.muted).textSelection(.enabled)
                            }
                        }
                    } footer: { Text("Only on this phone, not saved. Useful if a number came out wrong.") }
                }
                DatePicker("Test date", selection: $date, displayedComponents: .date)
                Picker("Lab in", selection: $region) {
                    ForEach(LabRegion.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                ForEach($rows) { $row in
                    Section(LabMarkers.name(row.code)) {
                        field($row)
                        Button("Remove", role: .destructive) { rows.removeAll { $0.id == row.id } }
                            .font(.subheadline)
                    }
                }
                Section {
                    Menu {
                        ForEach(unusedMarkers) { m in Button(m.name) { addRow(m.code) } }
                    } label: {
                        Label("Add a marker", systemImage: "plus")
                    }
                    .disabled(unusedMarkers.isEmpty)
                } footer: { Text("Add only what is on your report.") }
                Section { TextField("Note", text: $note, axis: .vertical) }
                if editing != nil {
                    Section {
                        Button("Delete these results", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Lab results" : "Edit results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(rows.allSatisfy { num($0.value) == nil })
                }
            }
            .confirmationDialog("Delete these results?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    editing?.results.forEach(context.delete)
                    try? context.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This cannot be undone.") }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task { await read(item) }
            }
            .onAppear(perform: load)
        }
    }

    private func field(_ row: Binding<Row>) -> some View {
        let units = LabMarkers.marker(row.wrappedValue.code)?.units ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Value", text: row.value)
                    .keyboardType(.decimalPad)
                    .font(.title3.monospacedDigit())
                if units.count > 1 {
                    Picker("Unit", selection: row.unit) {
                        ForEach(units, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                } else {
                    Text(row.wrappedValue.unit).foregroundStyle(Palette.muted)
                }
            }
            if let r = rangeText(row.wrappedValue) {
                Text(r).font(.caption).foregroundStyle(Palette.muted)
            }
        }
    }

    private func rangeText(_ row: Row) -> String? {
        if let r = row.labRange { return "Your lab's range \(fmt(r.0))–\(fmt(r.1)) \(row.unit)" }
        guard let r = LabMarkers.typicalRange(row.code, unit: row.unit, region: region) else { return nil }
        let place = region == .elsewhere ? "" : " in \(region.label)"
        return "Typical adult range\(place) \(fmt(r.0))–\(fmt(r.1)) \(row.unit). Your lab's may differ."
    }

    private func previousUnit(_ code: String) -> String {
        LabMarkers.defaultUnit(code, previous: allLabs.filter { $0.marker == code }.compactMap(\.unit))
    }

    private func addRow(_ code: String) {
        rows.append(Row(code: code, unit: previousUnit(code)))
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        region = LabRegion.guess(previous: allLabs.sorted { $0.date > $1.date }.map(\.labRegionRaw),
                                 localeRegion: Locale.current.region?.identifier)
        guard let report = editing else { return }
        if let r = report.results.compactMap(\.labRegionRaw).compactMap(LabRegion.init(rawValue:)).first { region = r }
        date = report.date
        note = report.results.compactMap(\.note).first ?? ""
        fromScreenshot = report.results.contains { $0.sourceRaw == "screenshot" }
        rows = report.results.map { l in
            var row = Row(code: l.marker, unit: l.unit.map(LabMarkers.canonical) ?? previousUnit(l.marker))
            row.value = l.value.map(fmt) ?? ""
            row.labRange = l.labRange
            return row
        }
    }

    private func read(_ item: PhotosPickerItem) async {
        reading = true
        defer { reading = false; photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let lines = await LabOCR.lines(from: data)
        readRows = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let r = LabParser.parse(lines: lines)
        if r.isEmpty {
            readNote = "No known lab results found in that image. You can add the markers and type the numbers in."
            return
        }
        let found = LabMarkers.all.compactMap { m in r[m.code].map { (m, $0) } }
        for (m, v) in found {
            let c = LabMarkers.canonical(v.unit ?? LabParser.guessUnit(code: m.code, value: v.value))
            let unit = m.units.contains(c) ? c : previousUnit(m.code)
            if let i = rows.firstIndex(where: { $0.code == m.code }) {
                rows[i].value = fmt(v.value); rows[i].unit = unit
                rows[i].labRange = v.low.flatMap { lo in v.high.map { (lo, $0) } }
            } else {
                var row = Row(code: m.code, unit: unit)
                row.value = fmt(v.value)
                row.labRange = v.low.flatMap { lo in v.high.map { (lo, $0) } }
                rows.append(row)
            }
        }
        if let d = r.date { date = d }
        fromScreenshot = true
        readNote = "Found \(found.map { $0.0.name }.joined(separator: ", "))\(r.date == nil ? "; no date, so check it" : " and the date"). Check each number and unit against the report before saving."
    }

    private func save() {
        let existing = editing?.results ?? []
        let reportId = existing.compactMap(\.reportId).first ?? UUID()
        let filled = rows.filter { num($0.value) != nil }
        let keep = Set(filled.map(\.code))
        for old in existing where !keep.contains(old.marker) { context.delete(old) }
        for row in filled {
            let l = existing.first { $0.marker == row.code } ?? {
                let n = LabResult(date: date, marker: row.code)
                n.sourceRaw = fromScreenshot ? "screenshot" : "manual"
                context.insert(n)
                return n
            }()
            l.date = date
            l.reportId = reportId
            l.value = num(row.value)
            l.unit = row.unit
            l.low = row.labRange?.0; l.high = row.labRange?.1
            l.note = note.isEmpty ? nil : note
            l.labRegion = region
            l.updatedAt = .now
        }
        try? context.save()
        dismiss()
    }

    private func num(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }
    private func fmt(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...3)).grouping(.never)) }
}

/// Every lab report, newest first, grouped by date. Tap to edit; swipe to delete.
struct LabListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LabResult.date, order: .reverse) private var labs: [LabResult]
    @State private var editing: LabReport?
    @State private var adding = false

    var body: some View {
        let reports = LabReport.group(labs)
        List {
            if reports.isEmpty { Text("No results yet.").foregroundStyle(Palette.muted) }
            ForEach(reports) { report in
                Button { editing = report } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.date.formatted(date: .long, time: .omitted)).font(.headline).foregroundStyle(Palette.ink)
                        Text(LabText.line(report)).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete { idx in
                idx.flatMap { reports[$0].results }.forEach(context.delete)
                try? context.save()
            }
        }
        .navigationTitle("Lab results")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add results") } }
        .sheet(item: $editing) { AddLabView(editing: $0) }
        .sheet(isPresented: $adding) { AddLabView() }
    }
}

enum LabText {
    /// One report with each marker's value, unit and the lab's own range when printed.
    static func detail(_ report: LabReport) -> String {
        report.results.compactMap { l in
            l.value.map { v in
                "\(l.markerName) \(v.formatted(.number.precision(.fractionLength(0...3))))" + (l.unit.map { " " + $0 } ?? "")
                    + (l.labRange.map { " (lab range \($0.0.formatted())–\($0.1.formatted()))" } ?? "")
            }
        }.joined(separator: ", ")
    }

    static func line(_ report: LabReport) -> String {
        report.results.compactMap { l in
            l.value.map { "\(l.markerName) \($0.formatted(.number.precision(.fractionLength(0...2))))\(l.unit.map { " " + $0 } ?? "")" }
        }.joined(separator: " · ")
    }
}

/// Every lab over time: labs come every few months, so this spans all of them,
/// with dose changes marked and the lab's own range drawn as dashed lines.
struct LabHistoryCard: View {
    let labs: [LabResult]
    let doses: [DoseChange]
    @State private var picked: String?

    /// Markers she has values for, in catalogue order.
    private var present: [LabMarker] {
        let have = Set(labs.filter { $0.value != nil }.map(\.marker))
        return LabMarkers.all.filter { have.contains($0.code) }
    }

    private var code: String? {
        if let picked, present.contains(where: { $0.code == picked }) { return picked }
        // The marker with the most results, else the first.
        return present.max { count($0.code) < count($1.code) }?.code
    }

    private func count(_ c: String) -> Int { labs.filter { $0.marker == c && $0.value != nil }.count }

    private var mine: [LabResult] { labs.filter { $0.marker == code }.sorted { $0.date > $1.date } }

    private var points: [(Date, Double)] {
        mine.compactMap { l in l.value.map { (l.date, $0) } }.sorted { $0.0 < $1.0 }
    }

    private var range: (Double, Double)? {
        mine.lazy.compactMap { $0.shownRange }.first.map { ($0.low, $0.high) }
    }

    private var unit: String? { mine.compactMap(\.unit).first }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lab history").font(.headline).foregroundStyle(Palette.ink)
                    Text("\(points.count) result\(points.count == 1 ? "" : "s")\(unit.map { ", \($0)" } ?? "")").font(.footnote).foregroundStyle(Palette.muted)
                }
                Spacer()
                if present.count > 1 {
                    Picker("Marker", selection: Binding(get: { code ?? "" }, set: { picked = $0 })) {
                        ForEach(present) { Text($0.name).tag($0.code) }
                    }
                    .tint(Palette.onTint)
                }
            }
            if points.count >= 1 {
                Chart {
                    if let range {
                        RuleMark(y: .value("Low", range.0)).foregroundStyle(Palette.muted.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        RuleMark(y: .value("High", range.1)).foregroundStyle(Palette.muted.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    ForEach(doses, id: \.syncId) { d in
                        RuleMark(x: .value("Dose", d.date)).foregroundStyle(Palette.dataMark.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                    ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("Date", p.0), y: .value("Value", p.1)).foregroundStyle(Palette.dataMark)
                        PointMark(x: .value("Date", p.0), y: .value("Value", p.1))
                            .foregroundStyle(Palette.dataMark)
                            .annotation(position: .top) { Text(p.1.formatted(.number.precision(.fractionLength(0...2)))).font(.caption2).foregroundStyle(Palette.ink) }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits)) } }
                .chartYAxis(.hidden)
                .frame(height: 160)
                .accessibilityElement()
                .accessibilityLabel(points.map { "\($0.0.formatted(date: .abbreviated, time: .omitted)): \($0.1)" }.joined(separator: ". "))
                if range != nil {
                    Text(mine.lazy.compactMap { $0.shownRange }.first?.fromLab == false
                         ? "Dashed lines: typical adult range for this unit (your report had none). Dotted lines: dose changes."
                         : "Dashed lines: the lab's own range from your latest report. Dotted lines: dose changes.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                } else {
                    Text("Dotted lines: dose changes.").font(.footnote).foregroundStyle(Palette.muted)
                }
            } else {
                Text("No lab results yet.").font(.subheadline).foregroundStyle(Palette.muted)
            }
        }
        .padding(18)
        .card()
    }
}
