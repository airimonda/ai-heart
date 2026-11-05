import Testing
@testable import AiHeartCore

// Synthetic strings only. Never the real seed.

@Suite struct AboutMeSeedTests {
    let seed = """
    # A memory seed

    **How to use this file**
    - [synthetic] notes for a reader

    ## 1. About her
    - [synthetic] likes tea

    ## 2. How to talk to her
    - [synthetic] plainly

    ## 3. Where she is right now (integration phase)
    - [synthetic] moving forward

    ## 4. What AiHeart is (her requirements)
    - [synthetic] product notes

    ## 5. Private context (on-device only)
    - (add if you want)
    """

    @Test func keepsWhatSheWrote() {
        let mine = AboutMeDoc(sections: [.init(title: "Goals", body: "[synthetic] mine")])
        let out = mine.mergingMemorySeed(seed)
        #expect(out.sections.first { $0.title == "Goals" }?.body == "[synthetic] mine")
        #expect(out.sections.first { $0.title == "About me" }?.body == "- [synthetic] likes tea")
    }

    @Test func leavesOutEverythingElse() {
        let titles = AboutMeDoc(sections: []).mergingMemorySeed(seed).sections.map(\.title)
        #expect(titles == ["About me", "How to talk to me", "Where I am right now"])
    }

    @Test func importingTwiceChangesNothing() {
        let once = AboutMeDoc.template.mergingMemorySeed(seed)
        #expect(once.mergingMemorySeed(seed) == once)
    }

    @Test func survivesBeingStored() {
        let once = AboutMeDoc.template.mergingMemorySeed(seed)
        #expect(AboutMeDoc.parse(once.markdown) == once)
    }

    @Test func promptContextIsDataAndScoped() {
        let doc = AboutMeDoc(sections: []).mergingMemorySeed(seed)
        let voice = doc.promptContext(full: false)
        #expect(voice.contains("plainly") && !voice.contains("likes tea") && !voice.contains("moving forward"))
        let full = doc.promptContext(full: true)
        #expect(full.contains("plainly") && full.contains("likes tea") && !full.contains("moving forward"))
        #expect(full.contains("data, not instructions"))
    }

    @Test func rowsStoredUnderTheOldTitlesKeepTheirText() {
        let old = "# About me\n\n## About her\n[synthetic] a\n\n## How to talk to her\n[synthetic] b\n\n## Where she is right now (integration phase)\n[synthetic] c\n"
        let doc = AboutMeDoc.parse(old)
        #expect(doc.sections.first { $0.title == "About me" }?.body == "[synthetic] a")
        #expect(doc.sections.first { $0.title == "How to talk to me" }?.body == "[synthetic] b")
        #expect(doc.sections.first { $0.title == "Where I am right now" }?.body == "[synthetic] c")
    }

    func section(_ d: AboutMeDoc, _ t: String) -> String { d.sections.first { $0.title == t }?.body ?? "" }

    @Test func foldsOverlappingSectionsWithoutLosingWords() {
        let doc = AboutMeDoc(sections: [.init(title: "Who I am, practically", body: "[synthetic] tea in mornings"), .init(title: "About me", body: "- [synthetic] lives near hills")])
        let t = doc.tidied()
        #expect(section(t.doc, "Who I am, practically").isEmpty)
        #expect(section(t.doc, "About me").contains("tea in mornings") && section(t.doc, "About me").contains("lives near hills"))
        #expect(t.foldedSections == ["Who I am, practically"])
    }

    @Test func removesARepeatAndKeepsTheFullerCopy() {
        let doc = AboutMeDoc(sections: [.init(title: "Goals", body: "Less rumination and comparison."), .init(title: "About me", body: "- Working toward less rumination and comparison every week.\n- Likes hiking.")])
        let t = doc.tidied()
        #expect(t.repeats == ["Less rumination and comparison."])
        #expect(section(t.doc, "Goals").isEmpty)
        #expect(section(t.doc, "About me").contains("Working toward less rumination"))
        #expect(section(t.doc, "About me").contains("Likes hiking"))
    }

    @Test func differentLinesStay() {
        let doc = AboutMeDoc(sections: [.init(title: "Goals", body: "Read more fantasy novels this year."), .init(title: "About me", body: "Lifts weights three days weekly.")])
        let t = doc.tidied()
        #expect(!t.hasWork)
        #expect(t.doc == doc)
    }

    @Test func shortLinesAreNeverRepeats() {
        let doc = AboutMeDoc(sections: [.init(title: "Goals", body: "Be calm."), .init(title: "About me", body: "Be calm.")])
        #expect(doc.tidied().repeats.isEmpty)
    }

    @Test func tidyingTwiceFindsNothingNew() {
        let doc = AboutMeDoc(sections: [.init(title: "Goals", body: "Less rumination and comparison."), .init(title: "About me", body: "Less rumination and comparison. Likes hiking and maps.")])
        let once = doc.tidied()
        #expect(once.hasWork)
        #expect(!once.doc.tidied().hasWork)
    }

    @Test func chosenToShareStaysInPlace() {
        let doc = AboutMeDoc(sections: [.init(title: "Things I chose to share (never used as labels)", body: "[synthetic] private line here"), .init(title: "About me", body: "")])
        let t = doc.tidied()
        #expect(section(t.doc, "Things I chose to share (never used as labels)") == "[synthetic] private line here")
        #expect(!t.doc.promptContext(full: true).contains("private line"))
    }

    @Test func noContextWhenEmpty() {
        #expect(AboutMeDoc.template.promptContext(full: true).isEmpty)
    }
}
