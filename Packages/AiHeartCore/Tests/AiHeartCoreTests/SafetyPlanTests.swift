import Foundation
import Testing
@testable import AiHeartCore

// Synthetic strings only.

@Suite struct SafetyPlanTests {
    func settings() -> AppSettings { AppSettings() }

    @Test func emptyPlanHasNoSections() {
        #expect(SafetyPlan.sections(from: settings()).isEmpty)
        #expect(SafetyPlan.sections(from: settings(), includeEmpty: true).count == 7)
    }

    @Test func sectionsFollowTheStepOrderAndSkipEmpty() {
        let s = settings()
        s.planPros = "[synthetic] clinic"
        s.planSigns = "  [synthetic] signs \n"
        s.safetyPage = "[synthetic] old page"
        s.planCoping = "   \n"
        let sec = SafetyPlan.sections(from: s)
        #expect(sec.map(\.step) == [.signs, .pros, .other])
        #expect(sec.map(\.title) == ["My warning signs", "Professionals I can call", "Anything else"])
        #expect(sec[0].text == "[synthetic] signs")
    }

    @Test func oldSafetyPageIsKeptAsAnythingElse() {
        let s = settings()
        s.safetyPage = "[synthetic] only the old page"
        let sec = SafetyPlan.sections(from: s)
        #expect(sec.count == 1 && sec[0].step == .other && sec[0].text == "[synthetic] only the old page")
    }

    @Test func stepsReadAndWriteTheirOwnField() {
        let s = settings()
        for step in SafetyPlan.Step.allCases { step.set("[synthetic] \(step.rawValue)", in: s) }
        #expect(s.planSigns == "[synthetic] 1" && s.planCoping == "[synthetic] 2" && s.planPlaces == "[synthetic] 3")
        #expect(s.planHelpers == "[synthetic] 4" && s.planPros == "[synthetic] 5" && s.planSafeSpace == "[synthetic] 6")
        #expect(s.safetyPage == "[synthetic] 7")
        #expect(SafetyPlan.Step.allCases.allSatisfy { $0.text(in: s) == "[synthetic] \($0.rawValue)" })
    }

    @Test func plainTextJoinsWrittenSteps() {
        let s = settings()
        s.planSigns = "a"; s.planHelpers = "b"
        #expect(SafetyPlan.plainText(from: s) == "My warning signs\na\n\nPeople I can ask for help\nb")
        #expect(SafetyPlan.plainText(from: settings()) == "")
    }

    @Test func copyHasNoExclamationMarks() {
        for step in SafetyPlan.Step.allCases {
            #expect(!step.title.contains("!") && !step.helper.contains("!"))
        }
    }

    @Test func findsPhoneNumbers() {
        let text = "[synthetic] Sam 090-1234-5678, clinic +81 3 5555 0100 or call 119."
        let urls = SafetyPlan.phoneMatches(in: text).map(\.url.absoluteString)
        #expect(urls == ["tel:09012345678", "tel:+81355550100", "tel:119"])
    }

    @Test func ignoresDatesAndShortNumbers() {
        let text = "[synthetic] 2026-11-04 I have 2 or 3 things, at 5 pm, room A12"
        #expect(SafetyPlan.phoneMatches(in: text).isEmpty)
    }

    @Test func linkifyMarksOnlyTheNumber() {
        let text = "[synthetic] Ring 119 now"
        let attr = SafetyPlan.linkified(text)
        #expect(String(attr.characters) == text)
        let links = attr.runs.filter { $0.link != nil }
        #expect(links.count == 1)
        #expect(links.first.map { String(attr[$0.range].characters) } == "119")
        #expect(SafetyPlan.linkified("[synthetic] no numbers").runs.allSatisfy { $0.link == nil })
    }
}
