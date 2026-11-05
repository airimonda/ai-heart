import AiHeartCore
import CoreGraphics
import SwiftData
import SwiftUI
import UIKit

/// Runs the word tasks through the model with every output checked. Returns nil when the
/// model is not available or nothing passed, so the UI simply shows nothing new.
@MainActor
enum WordFinder {
    static func quietTopics(_ context: ModelContext) -> [String] {
        ((try? context.fetch(FetchDescriptor<QuietTopic>())) ?? []).map(\.term)
    }

    static func vocabulary(_ context: ModelContext) -> [String] {
        let words = ((try? context.fetch(FetchDescriptor<Entry>())) ?? []).compactMap(\.word)
        return WordTasks.vocabulary(from: words)
    }

    /// A short caption for the vibe of a photo. Gemma only: the built-in rules cannot see images.
    static func vibe(_ data: Data, context: ModelContext) async -> String? {
        let llm = LLMService.shared
        NSLog("AiHeartLLM photo: downloaded=%d localCopy=%d state=%@", llm.isDownloaded ? 1 : 0, llm.hasLocalCopy ? 1 : 0, "\(llm.state)")
        if llm.isDownloaded, llm.state != .ready { await llm.prepare() }
        let model = llm.model(for: .photo)
        guard model.canSeeImages, let image = UIImage(data: data)?.cgImage else {
            NSLog("AiHeartLLM photo: no image model (state=%@)", "\(llm.state)")
            return nil
        }
        let system = "You give photos in a personal journal a short, gentle caption. Never diagnose, never label a state, never give advice."
        let request = GenerationRequest(system: system, prompt: WordTasks.vibePrompt(), image: image, maxTokens: 16, temperature: 0.5)
        let out = await OutputValidator.generate(model, request,
                                                 policy: OutputPolicy(input: request.prompt, quietTopics: quietTopics(context), maxCharacters: 60),
                                                 accept: WordTasks.parseVibe)
        NSLog("AiHeartLLM photo: result=%d last=%@", out == nil ? 0 : 1, OutputValidator.lastFailure ?? "-")
        return out
    }

    /// Words that might fit what she wrote, preferring her own vocabulary.
    static func forText(_ draft: String, context: ModelContext) async -> (words: [String], fromModel: Bool) {
        let vocab = vocabulary(context)
        let llm = LLMService.shared
        if llm.isDownloaded, llm.state != .ready { await llm.prepare() }
        let model = llm.model(for: .words)
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let prompt = WordTasks.findWordsPrompt(draft: trimmed, vocabulary: vocab)
            let out = await OutputValidator.generate(model, GenerationRequest(system: WordTasks.system, prompt: prompt, maxTokens: 40, ownText: trimmed),
                                                     policy: OutputPolicy(input: prompt, userText: trimmed, quietTopics: quietTopics(context), maxCharacters: 160)) {
                let w = WordTasks.parseWords($0, limit: 5)
                return w.count >= 2 ? w.joined(separator: ", ") : nil
            }
            if let out { return (WordTasks.parseWords(out, limit: 5), true) }
        }
        return (WordTasks.fallbackWords(vocabulary: vocab), false)
    }
}

/// "Words for this photo" under the capture box. Tapping one sets her word; she can
/// change it or ignore them all.
struct PhotoWords: View {
    let photo: Data
    let draft: CaptureDraft
    @Environment(\.modelContext) private var context
    @State private var caption: String?
    @State private var looking = false
    @State private var note: String?

    var body: some View {
        // A VStack with an always-present spacer: a Group with nothing inside never runs .task.
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 0)
            if looking {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(LLMService.shared.state == .ready ? "Finding a caption…" : "Loading the language model… the first time takes a little while.")
                }
                .font(.subheadline).foregroundStyle(Palette.muted)
            } else if let caption {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(caption).font(.journal(.body)).italic().foregroundStyle(Palette.ink)
                    Spacer()
                    Button("Use") {
                        let rest = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.text = rest.isEmpty ? caption : caption + "\n" + rest
                        GuessLog.noteWords(kind: "photoCaption", shown: [caption], picked: caption, context: context)
                        self.caption = nil
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minWidth: 44, minHeight: 44)
                    Button("Not this") {
                        GuessLog.noteWords(kind: "photoCaption", shown: [caption], picked: nil, context: context)
                        self.caption = nil
                    }
                    .font(.subheadline).foregroundStyle(Palette.muted).frame(minWidth: 44, minHeight: 44)
                }
            } else if let note {
                Text(note).font(.footnote).foregroundStyle(Palette.muted)
            }
        }
        .task(id: photo.hashValue) {
            caption = nil
            note = nil
            NSLog("AiHeartLLM photo task: downloaded=%d", LLMService.shared.isDownloaded ? 1 : 0)
            guard LLMService.shared.isDownloaded || LLMService.shared.state == .ready else { return }
            looking = true
            caption = await WordFinder.vibe(photo, context: context)
            looking = false
            if caption == nil {
                if case .failed(let msg) = LLMService.shared.state { note = msg }
                else if LLMService.shared.state != .ready { note = "The language model is not loaded." }
            }
        }
    }
}
