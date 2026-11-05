import Testing
@testable import AiHeartCore

// Synthetic text only. Never the private seed.

@Suite struct AboutMeTests {
    @Test func templateParsesToEmptySections() {
        let md = """
        # About me (template)

        Fill in what you want the app to know. Keep it short and in your own words. This stays on your device.

        ## Who I am, practically
        -

        ## Goals
        -
        """
        let doc = AboutMeDoc.parse(md)
        #expect(doc.isEmpty)
        #expect(doc.sections.map(\.title) .starts(with: ["Who I am, practically", "Goals"]))
        #expect(doc.sections.count == AboutMeDoc.templateTitles.count)
    }

    @Test func roundTripKeepsTextAndExtraSections() {
        var doc = AboutMeDoc.template
        doc.sections[0].body = "- [synthetic] Works with data.\n- Learning Japanese."
        doc.sections.append(.init(title: "Extra", body: "[synthetic] extra"))
        let again = AboutMeDoc.parse(doc.markdown)
        #expect(again == doc)
    }

    @Test func textBeforeHeadingsIsKept() {
        let doc = AboutMeDoc.parse("[synthetic] loose line\n\n## Goals\nRest more")
        #expect(doc.sections.first == .init(title: "Notes", body: "[synthetic] loose line"))
        #expect(doc.sections.first { $0.title == "Goals" }?.body == "Rest more")
    }
}
