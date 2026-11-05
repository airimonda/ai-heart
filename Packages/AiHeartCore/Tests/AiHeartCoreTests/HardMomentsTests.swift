import Foundation
import Testing
@testable import AiHeartCore

// Synthetic data only.

@Suite struct HardMomentsTests {
    @Test func everyStateHasOffersAndEveryTechniqueHasEvidence() {
        for s in HardState.allCases {
            let o = HardMoments.offers(for: s, tries: [])
            #expect(!o.shown.isEmpty && o.shown.count <= 3, "\(s)")
            #expect(o.shown.count + o.more.count == HardMoments.catalog.count, "nothing hidden for \(s)")
        }
        for t in HardMoments.catalog {
            #expect(!t.steps.isEmpty && !t.evidence.isEmpty && !t.fits.isEmpty, "\(t.id)")
        }
        #expect(Set(HardMoments.catalog.map(\.id)).count == HardMoments.catalog.count)
    }

    @Test func loopNeverLeadsWithReframing() {
        // Arguing with a looping thought can become checking (docs/15): reframing is not offered for loops.
        let o = HardMoments.offers(for: .loop, tries: [])
        #expect(!o.shown.contains { $0.id == "reframe" })
        #expect(o.shown.first?.id == "defuse")
    }

    @Test func fastStateOffersSleepAndDoesNotLeadWithWalking() {
        let o = HardMoments.offers(for: .fast, tries: [])
        #expect((o.shown + o.more).contains { $0.id == "sleep" })
        #expect(o.shown.first?.id != "walk")
    }

    @Test func herResultsReorderOnlyAfterEnoughTries() {
        func tries(_ id: String, _ n: Int, drop: Int) -> [TechniqueTry] {
            (0..<n).map { _ in TechniqueTry(techniqueId: id, state: .flooded, before: 7, after: 7 - drop) }
        }
        let base = HardMoments.offers(for: .flooded, tries: []).shown.map(\.id)
        // Two tries: not enough, order unchanged.
        #expect(HardMoments.offers(for: .flooded, tries: tries("quiet", 2, drop: 5)).shown.map(\.id) == base)
        // Three tries that eased it: goes first.
        #expect(HardMoments.offers(for: .flooded, tries: tries("quiet", 3, drop: 5)).shown.first?.id == "quiet")
        // Three tries that did not ease it: moves behind untried ones.
        let low = HardMoments.offers(for: .flooded, tries: tries(base[0], 3, drop: 0))
        #expect(low.shown.first?.id != base[0])
        // Other states are not affected.
        #expect(HardMoments.results(tries("quiet", 3, drop: 5), state: .heavy).isEmpty)
    }

    @Test func unratedTriesDoNotCount() {
        let t = (0..<5).map { _ in TechniqueTry(techniqueId: "sigh", state: .fast, before: 8, after: nil) }
        #expect(HardMoments.results(t, state: .fast).isEmpty)
    }
}

@Suite struct ListenAffirmationTests {
    let said = "[synthetic] Everyone at work is against me and I am right about it."

    @Test func rejectsAgreementAndSpecialMeaning() {
        for r in ["You're right about work.", "You are not crazy.", "It's a sign that work is wrong for you.",
                  "I understand you better than they do.", "I am real, and I am listening.", "Only you can see it."] {
            #expect(ListenRules.rejection(r, transcript: said, quietTopics: []) != nil, "\(r)")
        }
    }

    @Test func stillAcceptsPlainReflection() {
        #expect(ListenRules.rejection("You said everyone at work is against you.", transcript: said, quietTopics: []) == nil)
        #expect(ListenRules.rejection("You felt absolutely drained at work.",
                                      transcript: "[synthetic] I felt absolutely drained at work.", quietTopics: []) == nil)
    }
}
