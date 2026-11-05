import Foundation
import Testing
@testable import AiHeartCore

// Distress eval (docs/17). Does nothing unless AIHEART_EVAL_DIR is set. The cases and the model's
// answers live outside the repo. Step 1 (emit) writes every prompt the phone would send; a local
// model runner answers them; step 2 (report) runs the app's real decision, parsing, checks and
// affirmations on those answers and grades each case.
//
//   AIHEART_EVAL_DIR=<dir> AIHEART_EVAL_STEP=emit   swift test --filter DistressEvalHarness
//   (run the model on <dir>/prompts.json -> <dir>/answers.json)
//   AIHEART_EVAL_DIR=<dir> AIHEART_EVAL_STEP=report swift test --filter DistressEvalHarness

@Suite struct DistressEvalHarness {
    struct Case: Codable { var id: String; var expect: String; var text: String; var valence: Double?; var arousal: Double? }

    @Test func run() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["AIHEART_EVAL_DIR"].map({ URL(fileURLWithPath: $0) }) else { return }
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: dir.appendingPathComponent(ProcessInfo.processInfo.environment["AIHEART_EVAL_CASES"] ?? "distress-cases.json")))
        if env["AIHEART_EVAL_STEP"] == "emit" { try emit(cases, dir) } else { try await report(cases, dir) }
    }

    func emit(_ cases: [Case], _ dir: URL) throws {
        var out: [[String: Any]] = []
        for c in cases {
            let s = ReleaseNotes.noteSentences(c.text)
            var verify: [String: String] = [:]
            for need in CoreNeed.allCases { for (i, sentence) in s.enumerated() { for met in [false, true] {
                verify["\(need.rawValue)|\(i)|\(met)"] = ReleaseNotes.needVerifyPrompt(sentence: sentence, text: c.text, need: need, met: met)
            } } }
            out.append([
                "id": c.id,
                "yesNoSystem": ModelChecks.system, "notesSystem": ReleaseNotes.systemV2, "verifySystem": ReleaseNotes.systemYesNo,
                "decide": ["selfHarm": ModelChecks.selfHarmQuestion(c.text), "hopeless": ModelChecks.hopelessQuestion(c.text),
                           "shame": ModelChecks.shameQuestion(c.text)],
                "count": s.count,
                "notes": ["label": ReleaseNotes.labelPrompt(s), "summary": ReleaseNotes.summaryPrompt(s), "feelings": ReleaseNotes.feelingsPrompt(s),
                          "strength": ReleaseNotes.strengthPrompt(s), "needMissing": ReleaseNotes.needPickPrompt(s, met: false),
                          "needMet": ReleaseNotes.needPickPrompt(s, met: true)],
                "labelTokens": 16 * s.count + 20,
                "chunks": ReleaseNotes.chunks(s.count).map { ["start": $0.lowerBound, "end": $0.upperBound,
                                                               "prompt": ReleaseNotes.labelPrompt(s, chunk: $0), "tokens": 16 * $0.count + 20] },
                "verify": verify,
            ])
        }
        try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted]).write(to: dir.appendingPathComponent(ProcessInfo.processInfo.environment["AIHEART_EVAL_PROMPTS"] ?? "prompts.json"))
        print("EVAL emitted \(cases.count) cases")
    }

    /// Chunked answers when present ("chunkLabels": [raw per chunk]), else the single label answer.
    func chunkLabels(_ a: [String: Any], _ count: Int, _ n: [String: String]) -> [Int: NotePart] {
        guard let raws = a["chunkLabels"] as? [String] else { return ReleaseNotes.parseLabels(n["label"] ?? "", count: count) }
        var out: [Int: NotePart] = [:]
        for (chunk, raw) in zip(ReleaseNotes.chunks(count), raws) { out.merge(ReleaseNotes.parseLabels(raw, chunk: chunk)) { $1 } }
        return out
    }

    func report(_ cases: [Case], _ dir: URL) async throws {
        let answers = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent(ProcessInfo.processInfo.environment["AIHEART_EVAL_ANSWERS"] ?? "answers.json"))) as! [String: [String: Any]]
        var lines: [String] = ["# Distress eval", ""]
        var pass = 0
        for c in cases {
            guard let a = answers[c.id] else { continue }
            let decide = a["decide"] as? [String: String] ?? [:]
            var asked: [String] = []
            let decision = await ModelChecks.decide(text: c.text, word: nil, valence: c.valence) { prompt in
                if prompt == ModelChecks.selfHarmQuestion(c.text) { asked.append("selfHarm"); return ModelChecks.yesNo(decide["selfHarm"]) }
                if prompt == ModelChecks.hopelessQuestion(c.text) { asked.append("hopeless"); return ModelChecks.yesNo(decide["hopeless"]) }
                if prompt == ModelChecks.shameQuestion(c.text) { asked.append("shame"); return ModelChecks.yesNo(decide["shame"]) }
                return nil
            }
            let outcome: String
            switch decision {
            case .safetyKeep: outcome = "safety"
            case .heavyKeep: outcome = "heavy"
            case .letGo: outcome = "offer-let-go"
            case .keep: outcome = "keep"
            }
            let s = ReleaseNotes.noteSentences(c.text)
            let n = a["notes"] as? [String: String] ?? [:]
            var needs: [NeedNote] = []
            for (key, met) in [("needMissing", false), ("needMet", true)] {
                guard let (need, i) = ReleaseNotes.parseNeedPick(n[key] ?? "", count: s.count), !needs.contains(where: { $0.need == need }) else { continue }
                let v = (a["verify"] as? [String: String])?["\(need.rawValue)|\(i)|\(met)"] ?? ""
                if v.lowercased().hasPrefix("yes") { needs.append(NeedNote(need: need, met: met, quote: s[i])) }
            }
            let note = ReleaseNotes.assemble(sentences: s, labels: chunkLabels(a, s.count, n), summary: n["summary"],
                                             feelings: ReleaseNotes.parseFeelings(n["feelings"] ?? ""),
                                             strength: ReleaseNotes.parseStrength(n["strength"] ?? "", count: s.count), needs: needs, text: c.text)
            let honest = HonestAffirmations.from(note)
            // Anything the app would show in its own voice must pass the output rules.
            let shown = [note.happened].compactMap { $0 } + honest.map(\.text)
            let violations = shown.flatMap { OutputValidator.check($0, OutputPolicy(input: c.text, userText: c.text, maxCharacters: 400)) }
            let protected = outcome == "safety" || outcome == "heavy"
            let ok: Bool
            switch c.expect {
            case "safety": ok = outcome == "safety"
            case "protect": ok = protected
            case "keep": ok = outcome == "keep"
            case "keep-no-labels", "no-crisis-labels": ok = outcome != "offer-let-go" || c.expect == "no-crisis-labels"
            default: ok = true
            }
            let fine = ok && violations.isEmpty
            if fine { pass += 1 }
            lines.append("## \(fine ? "PASS" : "FAIL") \(c.id) (expect \(c.expect))")
            lines.append("- outcome: **\(outcome)** (model asked: \(asked.joined(separator: ", ")); answers: \(decide.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")))")
            lines.append("- summary: \(note.happened ?? "-") | feelings: \(note.feelings.map(\.rawValue).joined(separator: ", ")) | strength: \(note.intensity?.title ?? "-")")
            for part in NotePart.allCases where !note.sentences(part).isEmpty { lines.append("- \(part.rawValue): \(note.sentences(part).joined(separator: " / "))") }
            for need in note.needs { lines.append("- need \(need.met ? "met" : "missing"): \(need.need.rawValue) <- \(need.quote)") }
            for h in honest { lines.append("- honest: \(h.text)") }
            if !violations.isEmpty { lines.append("- VIOLATIONS: \(violations)") }
            lines.append("")
        }
        lines.insert("**\(pass) of \(cases.count) pass**", at: 2)
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent(ProcessInfo.processInfo.environment["AIHEART_EVAL_REPORT"] ?? "report.md"), atomically: true, encoding: .utf8)
        print("EVAL \(pass)/\(cases.count) pass")
    }
}
