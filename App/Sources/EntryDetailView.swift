import AiHeartCore
import SwiftData
import SwiftUI

/// Journal · Entry (screen 24). "How your body was" arrives with Apple Health in M2.
struct EntryDetailView: View {
    let entry: Entry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsRows: [AppSettings]
    @Query private var summaries: [DaySummary]
    @State private var player = VoicePlayer()
    @State private var confirmDelete = false
    @State private var scrubbing = false
    @State private var confirmLetGo = false
    @State private var showSafety = false

    private var restDays: Int { settingsRows.first?.restDays ?? 7 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let data = entry.photoData, let image = UIImage(data: data) {
                    // A fixed frame with the photo filled inside it, so a wide (landscape)
                    // photo can never widen the page and push the text off screen.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 360)
                        .overlay { Image(uiImage: image).resizable().scaledToFill() }
                        .clipped()
                        .overlay(alignment: .bottomLeading) {
                            if let caption = entry.caption {
                                Text(caption)
                                    .font(.journal(.title2).italic().weight(.semibold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.35), radius: 6)
                                    .padding(20)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.capture, style: .continuous))
                        .accessibilityLabel("Photo")
                }

                EntryFeelingRow(entry: entry)

                HStack(spacing: 12) {
                    EntryMarks(entry: entry)
                    if !entry.bodyRegions.isEmpty {
                        Text(bodySummary(regions: entry.bodyRegions, sensations: entry.sensations))
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                    }
                }

                if let audio = entry.audioData {
                    Button { player.toggle(audio) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: player.playing ? "stop.fill" : "play.fill")
                                .foregroundStyle(Palette.onTint)
                                .frame(width: 48, height: 48)
                                .background(Palette.tint1, in: Circle())
                            Text("Voice note · \(formatDuration(entry.audioSeconds ?? 0))")
                                .foregroundStyle(Palette.ink)
                            Spacer()
                        }
                        .padding(12)
                        .card()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.playing ? "Stop voice note" : "Play voice note")
                }

                if let text = entry.text.map({ entry.photoData != nil ? bodyAfterCaption($0) : $0 }), !text.isEmpty {
                    Text(text)
                        .font(.journal(.title3))
                        .foregroundStyle(Palette.ink)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                }

                LiveNotes(entry: entry)

                HowYourBodyWas(entry: entry, summaries: summaries, dayStart: settingsRows.first?.dayStartHour ?? 4)

                Divider().overlay(Palette.line)

                HStack {
                    Label("Kept", systemImage: "heart.fill")
                        .foregroundStyle(Palette.ink)
                        .labelStyle(KeptLabelStyle())
                    Spacer()
                    Button("Change") { confirmLetGo = true }
                        .font(.headline)
                        .foregroundStyle(Palette.onTint)
                        .frame(minWidth: 44, minHeight: 44)
                }

                Button("Delete this entry", role: .destructive) { NSLog("AiHeartUI delete: button"); confirmDelete = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle(entry.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: shareText) { Label("Share this entry", systemImage: "square.and.arrow.up") }
                    Button("Let it rest", systemImage: "leaf") { confirmLetGo = true }
                    if entry.status == .kept, !(entry.text ?? "").isEmpty {
                        Button("Take out embarrassing parts", systemImage: "text.badge.checkmark") { scrubbing = true }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { NSLog("AiHeartUI delete: menu"); confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        // Hold to let go (docs/19). The let-go runs once the sheet has closed.
        .letGoConfirm(isPresented: $confirmLetGo) { letGo() }
        // An alert, not a second confirmationDialog: SwiftUI shows only one dialog per view.
        .alert("Delete this entry?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                dismiss()
                EntryActions.delete(entry, context: context)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It goes to Recently deleted in your journal for 30 days.")
        }
        .sheet(isPresented: $showSafety) { SafetyPageView(readOnly: true) }
        .sheet(isPresented: $scrubbing) { ScrubSheet(entry: entry) { scrubbing = false } }
        .onDisappear { if player.playing, let a = entry.audioData { player.toggle(a) } }
    }

    private var shareText: String {
        var parts = [entry.createdAt.formatted(date: .long, time: .shortened)]
        if let w = entry.word { parts.append(w) }
        if let t = entry.text { parts.append(t) }
        return parts.joined(separator: "\n\n")
    }

    private func bodyAfterCaption(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func letGo() {
        do {
            try EntryLifecycle.letGo(entry, restDays: max(restDays, 1), keptLines: KeepOrRelease.keptLines(entry.text ?? ""))
            try? context.save()
            ReleaseNoteWriter.writeLater(entry, context: context)
            dismiss()
        } catch LifecycleError.safetyKeep {
            // Never released. Keep it and open her Safety page.
            showSafety = true
        } catch {}
    }
}

struct KeptLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.foregroundStyle(Palette.action)
            configuration.title
        }
    }
}

/// "How your body was" on the entry's anchored day. Cycle (M4), training (M5) and media (M18)
/// rows join later.
struct HowYourBodyWas: View {
    let entry: Entry
    let summaries: [DaySummary]
    let dayStart: Int
    @Query private var settingsRows: [AppSettings]
    @Query private var workouts: [Workout]

    var body: some View {
        let snap = BodySnapshot.cached(summaries, settings: settingsRows.first)
        let day = DayAnchor.day(for: entry.createdAt, timeZone: entry.timeZone, dayStartHour: dayStart)
        let signals = [Signal.sleep, .restingHR, .hrv, .steps].filter { snap.value($0, on: day) != nil }
        let training = workouts.filter { DayAnchor.day(for: $0.start, timeZone: .current, dayStartHour: dayStart) == day }
        if !signals.isEmpty || snap.cycleLabel(day) != nil || !training.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("How your body was")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .padding(.leading, 6)
                VStack(spacing: 0) {
                    ForEach(Array(signals.enumerated()), id: \.offset) { i, s in
                        if i > 0 { Divider().overlay(Palette.line).padding(.leading, 18) }
                        BodyRow(signal: s, snap: snap, day: day)
                    }
                    if let label = snap.cycleLabel(day) {
                        if !signals.isEmpty { Divider().overlay(Palette.line).padding(.leading, 18) }
                        HStack {
                            Text("Cycle").font(.headline).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(label + " (estimated)").font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }
                    ForEach(training, id: \.syncId) { w in
                        Divider().overlay(Palette.line).padding(.leading, 18)
                        HStack {
                            Text("Training").font(.headline).foregroundStyle(Palette.ink)
                            Spacer()
                            Text([WorkoutFormat.title(w), "\(w.minutes) min", w.rpe.map { "RPE \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(Palette.muted)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }
                }
                .card()
            }
        }
    }
}

/// Set or change how an entry felt, after saving (owner, 2026-11-01). One tap gives the
/// entry a mood point, so the calendar and journal can color it.
struct EntryFeelingRow: View {
    let entry: Entry
    @Environment(\.modelContext) private var context
    @State private var open = false
    @State private var padOpen = false

    private static let words = ["Excited", "Bright", "Content", "Calm", "Okay", "Tired", "Low", "Tense", "Restless", "Wired"]
        .filter { MoodWords.point(for: $0) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if entry.moodGuessed, let v = entry.valence, let a = entry.arousal, !open {
                Text("AiHeart's guess from your words: \(MoodGuess.describe(valence: v, arousal: a))")
                    .font(.subheadline).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Chip(title: "Fits") { entry.moodGuessed = false; entry.updatedAt = .now; try? context.save() }
                    Chip(title: "Change") { padOpen = true }
                }
            } else if let w = entry.word, entry.valence != nil, !open {
                HStack {
                    Text("Felt").foregroundStyle(Palette.muted)
                    Text(w).font(.headline).foregroundStyle(Palette.ink)
                    Spacer()
                    Button("Change") { open = true }.font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
                }
            } else {
                Text(entry.valence == nil ? "How did it feel?" : "Change how it felt").font(.headline).foregroundStyle(Palette.ink)
                FlowLayout(spacing: 8) {
                    ForEach(Self.words, id: \.self) { w in
                        Chip(title: w, selected: entry.word == w) { set(w) }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sheet(isPresented: $padOpen) { GuessedPointPad(entry: entry) }
    }

    private func set(_ w: String) {
        guard let p = MoodWords.point(for: w) else { return }
        entry.moodGuessed = false
        entry.word = w
        entry.valence = p.valence
        entry.arousal = p.arousal
        entry.updatedAt = .now
        try? context.save()
        open = false
    }
}
