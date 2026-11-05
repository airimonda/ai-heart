import Testing
@testable import AiHeartCore

// Synthetic readings only.

@Suite struct UrgentSignsTests {
    @Test func quietWhenOrdinary() {
        #expect(UrgentSigns.check(.init(heartRate: 72, systolic: 118, diastolic: 76, sensations: ["Tired", "Cold"])).isEmpty)
        #expect(UrgentSigns.check(.init(heartRate: 105, sensations: ["Racing", "Hot"])).isEmpty)
    }

    @Test func thresholds() {
        #expect(UrgentSigns.check(.init(systolic: 182, diastolic: 95)).map(\.id) == ["bp"])
        #expect(UrgentSigns.check(.init(systolic: 150, diastolic: 121)).map(\.id) == ["bp"])
        #expect(UrgentSigns.check(.init(systolic: 179, diastolic: 119)).isEmpty)
        #expect(UrgentSigns.check(.init(heartRate: 125)).map(\.id) == ["hr"])
        #expect(UrgentSigns.check(.init(heartRate: 38)).map(\.id) == ["hr"])
        #expect(UrgentSigns.check(.init(signs: [.chestPain])).map(\.id) == ["chest"])
    }

    @Test func combinations() {
        let fast = UrgentSigns.check(.init(heartRate: 115, signs: [.fever], sensations: ["Shaky"]))
        #expect(fast.map(\.id).contains("racingHeat"))
        let slow = UrgentSigns.check(.init(heartRate: 46, signs: [.confused], sensations: ["Cold"]))
        #expect(slow.map(\.id).contains("drowsyCold"))
        #expect(!slow.map(\.id).contains("confused"))
        #expect(UrgentSigns.check(.init(signs: [.confused])).map(\.id) == ["confused"])
    }

    @Test func noLabelsInCopy() {
        let all = UrgentSigns.check(.init(heartRate: 130, systolic: 190, diastolic: 125,
                                          signs: Set(UrgentSigns.Sign.allCases), sensations: ["Racing", "Hot", "Shaky"]))
        for f in all {
            let t = (f.what + " " + f.why).lowercased()
            for banned in ["storm", "crisis", "myxedema", "coma", "attack", "stroke", "you have", "diagnos"] {
                #expect(!t.contains(banned))
            }
        }
        #expect(UrgentSigns.emergencyNumber(region: "JP") == "119")
        #expect(UrgentSigns.emergencyNumber(region: "PH") == "911")
        #expect(UrgentSigns.plausible(systolic: 80, diastolic: 120) == nil)
        #expect(UrgentSigns.plausible(hr: 400) == nil)
    }
}
