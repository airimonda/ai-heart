import Foundation

/// Honest affirmations (owner, 2026-11-04: "affirmations, but only honest ones"; docs/16).
/// Generic positive self-statements ("I am lovable") made people with low self-esteem feel worse
/// (Wood, Perunovic and Lee 2009). What helps is affirming one's own values and acts, and
/// self-compassion. So each line is a fixed template, chosen only when her own labelled
/// sentences back it, and filled with her words. Never a trait ("you are strong"), never a promise
/// ("it will be fine"), never written by the model.
///
/// Owner, 2026-11-04: "they sound the same for all entries". So lines that quote something specific
/// from this entry come first, each kind has a few wordings picked per entry, and the generic
/// "this was hard" line is only a last resort.
public struct Affirmation: Equatable, Sendable {
    public let text: String
    /// Why it is true, shown under it.
    public let basis: String
}

public enum HonestAffirmations {
    public static let maxShown = 2

    /// Words that mark a repeated pattern, not a one-off event. English, Japanese, Tagalog.
    static let habitCues = ["again", "keep ", "keeps ", "always", "habit", "every time", "whenever", "when things",
                            "また", "いつも", "癖", "ulit", "lagi", "palagi"]
    /// A "want" that is avoidance is not a value to affirm (and the app never asks her to recount).
    static let avoidance = ["don't want to think", "dont want to think", "don't want to remember", "don't want to talk",
                            "don't want to feel", "forget", "思い出したくない", "考えたくない"]
    /// Acts of looking after herself in the moment.
    static let copingCues = ["breath", "walk", "called", "texted my", "made tea", "drank water", "got off", "stepped", "stood back",
                             "stood far", "sat down", "lay down", "went outside", "left the", "took a", "shower", "cafe", "café",
                             "asked", "told ", "wrote", "stretched", "slept", "rested", "put my phone", "turned off",
                             "深呼吸", "散歩", "電話", "huminga", "naglakad", "tumawag"]
    static let unpleasant: Set<NoteFeeling> = [.sad, .hurt, .lonely, .angry, .frustrated, .scared, .anxious, .ashamed, .guilty,
                                               .disappointed, .overwhelmed, .tired, .numb, .jealous, .helpless, .confused]

    /// Picks one wording per entry: stable for the same entry, different across entries.
    static func pick(_ options: [String], seed: Int, salt: Int) -> String {
        options[abs((seed &+ salt &* 7919) % options.count)]
    }

    static func q(_ s: String) -> String { "\u{201C}\(s)\u{201D}" }

    public static func from(_ note: ReleaseNote) -> [Affirmation] {
        let all = (note.parts ?? [:]).values.flatMap { $0 }.joined() + (note.happened ?? "")
        let seed = all.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        let want = note.sentences(.want).first { w in !avoidance.contains(where: w.lowercased().contains) }
        let helped = note.sentences(.helped).first ?? note.helped.first
        let chain = note.sentences(.trigger) + note.sentences(.action) + note.sentences(.payoff) + note.sentences(.cost)
        let isHabit = chain.contains { c in habitCues.contains(where: c.lowercased().contains) }
        // Not for flashbacks or intrusive images: those recur but are not something she does for a payoff.
        let sawSteps = isHabit && !note.sentences(.action).isEmpty
            && (!note.sentences(.payoff).isEmpty || !note.sentences(.cost).isEmpty)
        let coping = (note.sentences(.action) + note.sentences(.helped)).first { a in
            copingCues.contains(where: a.lowercased().contains) && !habitCues.contains(where: a.lowercased().contains)
        }
        // Never hold up a thought of self-harm or hopelessness as something to look at.
        let thought = note.sentences(.thought).first { t in !SafetyCheck.mentionsSelfHarm(t) && !KeepOrRelease.readsHopeless(t) }
        let named = note.feelings.filter(unpleasant.contains)
        // Credit only feelings she named herself; the fixed-list feelings are the model's picks.
        let herWords = all.lowercased()
        let namedByHer = named.filter { f in f.cues.contains(where: herWords.contains) }
        let selfConscious = note.feelings.first { [.ashamed, .guilty, .disappointed, .lonely].contains($0) }
        // Hard only when it read strong and the feelings are mostly unpleasant (not "I feel amazing").
        let hard = (note.intensity == .strong || note.intensity == .veryStrong)
            && named.count >= min(2, max(1, note.feelings.count))

        // Specific first (each quotes this entry), then general.
        // Never affirm a sentence about self-harm or hopelessness.
        func safe(_ t: String) -> Bool { !SafetyCheck.mentionsSelfHarm(t) && !KeepOrRelease.readsHopeless(t) }
        var specific: [Affirmation] = []
        var general: [Affirmation] = []

        if let coping, coping != helped {
            specific.append(Affirmation(text: pick([
                "In the middle of it, you did something for yourself: \(q(coping))",
                "You looked after yourself while it was happening: \(q(coping))",
                "\(q(coping)) That was you taking care of yourself, right then.",
            ], seed: seed, salt: 1), basis: "Your own words. Noticing what you already do to cope is part of strengths-based therapy."))
        }
        if let want {
            specific.append(Affirmation(text: pick([
                "You wrote what you want: \(q(want))" + (hard ? " Even now, you know what matters to you." : ""),
                "\(q(want)) That is a value of yours, in your own words.",
                "Under all of this, you named what you want: \(q(want))",
            ], seed: seed, salt: 2), basis: "Your own words. Holding on to your values is what self-affirmation research found helps under stress."))
        }
        if let proud = note.sentences(.proud).first(where: safe) {
            specific.append(Affirmation(text: pick([
                "You wrote what you are proud of: \(q(proud))",
                "\(q(proud)) That is yours. You named it yourself.",
            ], seed: seed, salt: 9), basis: "Your own words. Affirming what you value in yourself is what self-affirmation research found helps."))
        }
        if let longing = note.sentences(.longing).first(where: safe) {
            specific.append(Affirmation(text: pick([
                "What you long for, \(q(longing)), is one of the most basic human needs. It is not too much to want.",
                "\(q(longing)) Wanting this is human. Everyone needs to be cared for.",
            ], seed: seed, salt: 10), basis: "Needing care and closeness is a core emotional need in schema therapy and attachment research."))
        }
        if let helped {
            specific.append(Affirmation(text: pick([
                "Something helped: \(q(helped)) You found that, and it is yours to use again.",
                "\(q(helped)) Worth remembering for next time: it was yours.",
            ], seed: seed, salt: 3), basis: "Your own words. Building on what already works is part of strengths-based therapy."))
        }
        if sawSteps {
            let act = note.sentences(.action).first ?? ""
            specific.append(Affirmation(text: pick([
                "You caught the pattern while it was happening: \(q(act)) Seeing it clearly is the same work a chain analysis in therapy does.",
                "You wrote out the steps of the habit, including what you do: \(q(act)) That is how it gets looked at in therapy too.",
            ], seed: seed, salt: 4), basis: "Your sentences were sorted into those steps. Chain analysis is a core tool of dialectical behaviour therapy."))
        }
        if let thought, hard {
            specific.append(Affirmation(text: pick([
                "You wrote the thought down: \(q(thought)) On the page, it is a thought you had, and you can look at it.",
                "You caught the thought \(q(thought)) and put it outside your head.",
            ], seed: seed, salt: 5), basis: "Writing a thought down and looking at it from a step back lowered distress across many studies (self-distancing)."))
        }
        if namedByHer.count >= 2 {
            let list = namedByHer.prefix(3).map(\.rawValue).joined(separator: ", ")
            specific.append(Affirmation(text: pick([
                "You told your feelings apart: \(list). Naming them that precisely goes with coping better.",
                "Not just \u{201C}bad\u{201D}: \(list). You named what it actually was.",
            ], seed: seed, salt: 6), basis: "People who tell their feelings apart more finely tend to cope better (emotional granularity research)."))
        }
        if isHabit, !note.sentences(.payoff).isEmpty {
            general.append(Affirmation(text: "Reaching for something that brings quick relief is a very human response. It is how many habits form.",
                                       basis: "Behaviour that brings relief gets repeated; this is how habits are learned, for everyone."))
        }
        if let f = selfConscious {
            general.append(Affirmation(text: pick([
                "Feeling \(f.rawValue) after something like this is common. You are not the only one who feels it.",
                "Lots of people feel \(f.rawValue) in moments like this. It is a human feeling, not a verdict on you.",
            ], seed: seed, salt: 7), basis: "Self-compassion research: remembering that others feel this too eases self-criticism."))
        }
        if hard {
            general.append(Affirmation(text: pick([
                "This was hard, and you still put it into words.",
                "You wrote this while it was heavy. Putting it into words is not nothing.",
            ], seed: seed, salt: 8), basis: "You wrote it down. Putting feelings into words lowered emotional reactivity in lab studies."))
        }

        // Rotate the specific ones so two entries with the same kinds do not open the same way.
        let rotated = specific.isEmpty ? [] : Array(specific[(seed % specific.count)...] + specific[..<(seed % specific.count)])
        return Array((rotated + general).prefix(maxShown))
    }
}
