import AiHeartCore
import SwiftData
import SwiftUI
import UIKit

/// The model guesses an entry's tone when she did not pick a feeling (owner, 2026-11-01). Stored as
/// toneValence/toneArousal, used only to color the calendar and journal. Runs a few entries at a time, one
/// model call at a time, and not at all while she is paused. Text goes to the cloud model only when she turned
/// it on (owner, 2026-11-05), and never an entry that mentions hurting yourself (the on-device model reads
/// those instead); photos always stay on the phone.
@MainActor
enum ToneGuesser {
    private static var running = false
    static let perRun = 6

    static func needsTone(_ e: Entry) -> Bool {
        e.valence == nil && e.toneValence == nil && e.status == .kept && e.deviceId != DemoData.tag
            && (!(e.text ?? "").isEmpty || e.thumbData != nil)
    }

    /// Right after a save: when she wrote a lot and did not place a mood point, the model's tone
    /// guess also becomes the entry's mood point, marked as a guess (docs/19). Her tap in the
    /// meantime wins. If the model is not on the phone, nothing is set here and the later tone
    /// path colours the card as before. Saved-from-now entries only; nothing is backfilled.
    static func guessMood(for entry: Entry, context: ModelContext) async {
        guard !AiHeartStore.settings(in: context).pauseEverything else { return }
        guard MoodGuess.shouldGuess(text: entry.text, valence: entry.valence), entry.status == .kept,
              entry.deviceId != DemoData.tag, let text = entry.text else { return }
        let llm = LLMService.shared
        guard llm.isDownloaded else { return }
        if llm.state != .ready { await llm.prepare() }
        guard llm.canAnswer(.tone) else { return }
        let req = GenerationRequest(system: "You rate the feeling of personal journal entries with two numbers. Never explain.",
                                    prompt: WordTasks.tonePrompt(text: text), maxTokens: 20, temperature: 0.1, ownText: text)
        guard let raw = try? await llm.model(for: .tone).generate(req), let t = WordTasks.parseTone(raw) else { return }
        // She may have tapped, or let it go, while the model was working.
        guard entry.valence == nil, entry.status == .kept || (entry.status == .resting && entry.keepNumbers) else { return }
        entry.toneValence = t.valence
        entry.toneArousal = t.arousal
        entry.valence = t.valence
        entry.arousal = t.arousal
        entry.moodGuessed = true
        entry.updatedAt = .now
        try? context.save()
        NSLog("AiHeartLLM mood guessed for a long entry")
    }

    /// Guess tones for entries that have none yet. Safe to call often.
    static func run(_ context: ModelContext) async {
        guard !running, !AiHeartStore.settings(in: context).pauseEverything else { return }
        let llm = LLMService.shared
        guard llm.isDownloaded else { return }
        running = true
        defer { running = false }
        let all = (try? context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        let todo = Array(all.filter(needsTone).prefix(perRun))
        guard !todo.isEmpty else { return }
        if llm.state != .ready { await llm.prepare() }
        guard llm.canAnswer(.tone) || llm.canAnswer(.photo) else { return }
        var done = 0
        for e in todo {
            let text = e.text
            var image: CGImage?
            // Background only: no model swap for a photo-only entry when the model has no eyes of its own.
            if (text ?? "").isEmpty, llm.choice.seesImages, let d = e.thumbData { image = UIImage(data: d)?.cgImage }
            if (text ?? "").isEmpty && image == nil { continue }
            let req = GenerationRequest(system: "You rate the feeling of personal journal entries with two numbers. Never explain.",
                                        prompt: WordTasks.tonePrompt(text: text), image: image, maxTokens: 20, temperature: 0.1,
                                        ownText: text ?? "")
            // A photo never goes to the cloud: its tone is read on the phone.
            guard let raw = try? await llm.model(for: image == nil ? .tone : .photo).generate(req), let t = WordTasks.parseTone(raw) else { continue }
            e.toneValence = t.valence
            e.toneArousal = t.arousal
            // A long entry saved since mood guessing began, when the model was not ready at save:
            // the guess also becomes its mood point now, marked as a guess. Older entries stay colour-only.
            if e.createdAt >= MoodGuess.startedAt, MoodGuess.shouldGuess(text: e.text, valence: e.valence) {
                e.valence = t.valence
                e.arousal = t.arousal
                e.moodGuessed = true
            }
            done += 1
        }
        if done > 0 { try? context.save() }
        NSLog("AiHeartLLM tone: guessed=%d of %d", done, todo.count)
    }
}
