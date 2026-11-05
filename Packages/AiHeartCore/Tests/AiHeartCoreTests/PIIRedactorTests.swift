import Foundation
import Testing
@testable import AiHeartCore

// Synthetic text only.

@Suite struct PIIRedactorTests {
    @Test func contactDetailsAreReplacedAndRestored() {
        let t = "[synthetic] Email me at jane.doe@example.com or call +81 90-1234-5678. See https://example.com/x and @janed. Card 4111111111111111."
        let r = PIIRedactor.redact(t)
        for leak in ["jane.doe@example.com", "90-1234-5678", "example.com/x", "@janed", "4111111111111111"] {
            #expect(!r.text.contains(leak), "\(leak)")
        }
        #expect(r.restore(r.text) == t)
    }

    @Test func namesPlacesAndOrganisationsAreReplaced() {
        let t = "[synthetic] Yesterday Maria Santos and I had lunch in Chicago before her shift at Microsoft."
        let r = PIIRedactor.redact(t)
        #expect(!r.text.contains("Maria"))
        #expect(!r.text.contains("Chicago"))
        #expect(r.restore(r.text) == t)
    }

    @Test func samePersonGetsTheSamePlaceholderAcrossParts() {
        let r = PIIRedactor.redact(["[synthetic] Kenji called.", "[synthetic] I miss Kenji."])
        let p = r.map.first { $0.value == "Kenji" }?.key
        #expect(p != nil && r.texts.allSatisfy { $0.contains(p!) })
    }

    @Test func extraTermsAndMeaningfulWordsStay() {
        let r = PIIRedactor.redact("[synthetic] I cried calling out Mama at 3am. Ate at Lolas place.", extraTerms: ["Lolas place"])
        #expect(r.text.contains("Mama"))
        #expect(r.text.contains("3am"))
        #expect(!r.text.contains("Lolas place"))
    }

    @Test func modelRepliesWithPlaceholdersComeBackWhole() {
        let r = PIIRedactor.redact("[synthetic] Maria Santos said I was lazy.")
        let reply = "SUMMARY: You felt hurt by what " + (r.map.first { $0.value.contains("Maria") }?.key ?? "?") + " said."
        #expect(r.restore(reply).contains("Maria"))
    }
}
