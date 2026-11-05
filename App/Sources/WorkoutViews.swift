import AiHeartCore
import SwiftData
import SwiftUI

/// Rate this workout (replaces Log a workout, screen 17). The session itself comes from
/// Health and Hevy; she adds only what they cannot know.
struct RateWorkoutView: View {
    let workout: Workout
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allSets: [HevySet]
    @State private var rpe: Double = 6
    @State private var touched = false
    @State private var focus: WorkoutFocus?
    @State private var note = ""

    private var sets: [HevySet] {
        guard let id = workout.hevyId else { return [] }
        return allSets.filter { $0.hevyWorkoutId == id }.sorted { ($0.exerciseIndex, $0.setIndex) < ($1.exerciseIndex, $1.setIndex) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rate this workout")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Palette.ink)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                    }

                    sourceCard

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("How hard was it?").font(.headline).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(touched ? "\(Int(rpe))" : "–")
                                .font(.largeTitle.bold())
                                .foregroundStyle(Palette.onTint)
                                .monospacedDigit()
                        }
                        Slider(value: $rpe, in: 1...10, step: 1) { Text("Effort") } onEditingChanged: { _ in touched = true }
                            .tint(Palette.pink)
                            .accessibilityValue(touched ? "\(Int(rpe)) of 10" : "not set")
                        HStack {
                            Text("Easy"); Spacer(); Text("Max effort")
                        }
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                    }
                    .padding(18)
                    .card()

                    if workout.kind == .strength {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Focus, if you like").font(.subheadline).foregroundStyle(Palette.muted)
                            FlowLayout(spacing: 10) {
                                ForEach(WorkoutFocus.allCases, id: \.self) { f in
                                    Chip(title: f.label, selected: focus == f) { focus = focus == f ? nil : f }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("A note, if you like").font(.subheadline).foregroundStyle(Palette.muted)
                        TextField("How it went", text: $note, axis: .vertical)
                            .font(.journal(.body))
                            .lineLimit(2...6)
                    }
                    .padding(18)
                    .card()

                    Button("Save", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!touched && focus == nil && note.isEmpty)
                        .opacity(!touched && focus == nil && note.isEmpty ? 0.5 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Palette.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
            }
        }
        .onAppear {
            if let r = workout.rpe { rpe = Double(r); touched = true }
            focus = workout.focus
            note = workout.note ?? ""
        }
    }

    private var subtitle: String {
        let when = workout.start.formatted(.dateTime.weekday(.wide).hour().minute())
        return "\(workout.title ?? workout.kind.label) · \(when)"
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(workout.healthId != nil ? (workout.hevyId != nil ? "From Health and Hevy" : "From Health") : "From Hevy")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
            Text(WorkoutFormat.stats(workout))
                .font(.headline)
                .foregroundStyle(Palette.ink)
            if !sets.isEmpty {
                let names = Array(NSOrderedSet(array: sets.map(\.exerciseName))) as? [String] ?? []
                Text("\(names.count) exercise\(names.count == 1 ? "" : "s"), \(sets.filter { $0.setType != "warmup" }.count) working sets")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                if let top = WorkoutFormat.topSet(sets) {
                    Text("Top set: \(top)").font(.subheadline).foregroundStyle(Palette.muted)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func save() {
        if touched { workout.rpe = Int(rpe) }
        workout.focus = focus
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        workout.note = n.isEmpty ? nil : n
        workout.ratedAt = .now
        workout.promptedAt = workout.promptedAt ?? .now
        workout.updatedAt = .now
        try? context.save()
        dismiss()
    }
}

enum WorkoutFormat {
    static func stats(_ w: Workout) -> String {
        var parts = ["\(w.minutes) min"]
        if let k = w.activeKcal { parts.append("\(Int(k.rounded())) kcal") }
        if let hr = w.avgHR { parts.append("avg heart rate \(Int(hr.rounded()))") }
        return parts.joined(separator: " · ")
    }

    static func topSet(_ sets: [HevySet]) -> String? {
        guard let s = sets.filter({ $0.setType != "warmup" && ($0.weightKg ?? 0) > 0 && $0.reps != nil })
            .max(by: { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) }) else { return nil }
        let w = s.weightKg ?? 0
        let kg = w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
        return "\(s.exerciseName) \(kg) kg × \(s.reps ?? 0)"
    }

    static func title(_ w: Workout) -> String {
        if let f = w.focus, w.kind == .strength { return "Strength · \(f.label.lowercased())" }
        return w.title ?? w.kind.label
    }

    static func relativeDay(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide))
    }
}

/// Recent workouts on Insights · Today. Unrated ones offer "Rate".
struct WorkoutList: View {
    let workouts: [Workout]
    @State private var rating: Workout?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(workouts.enumerated()), id: \.element.syncId) { i, w in
                if i > 0 { Divider().overlay(Palette.line).padding(.leading, 64) }
                Button { rating = w } label: { WorkoutRow(workout: w) }
                    .buttonStyle(.plain)
            }
        }
        .sheet(item: $rating) { RateWorkoutView(workout: $0) }
    }
}

struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.kind.symbol)
                .foregroundStyle(Palette.onTint)
                .frame(width: 44, height: 44)
                .background(Palette.tint1, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(WorkoutFormat.title(workout)).font(.headline).foregroundStyle(Palette.ink).lineLimit(1)
                Text([WorkoutFormat.relativeDay(workout.start), "\(workout.minutes) min", workout.rpe.map { "RPE \($0)" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 4)
            if workout.isRated {
                if let k = workout.activeKcal {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(Int(k.rounded()))").font(.headline).foregroundStyle(Palette.ink)
                        Text("kcal").font(.caption).foregroundStyle(Palette.muted)
                    }
                }
            } else {
                Text("Rate")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.onTint)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Palette.tint1, in: Capsule())
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(workout.isRated ? "Change rating" : "Rate this workout")
    }
}
