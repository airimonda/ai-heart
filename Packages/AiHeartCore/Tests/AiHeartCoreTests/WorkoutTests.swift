import Foundation
import Testing
@testable import AiHeartCore

// Synthetic workouts and JSON only.

@Suite struct WorkoutTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func span(_ startMin: Double, _ endMin: Double) -> (start: Date, end: Date) {
        (t0.addingTimeInterval(startMin * 60), t0.addingTimeInterval(endMin * 60))
    }

    @Test func matchesWithinTolerance() {
        #expect(WorkoutMatch.sameSession(span(0, 50), span(3, 55)))
        #expect(WorkoutMatch.sameSession(span(0, 50), span(58, 70)))   // 8 min gap
        #expect(!WorkoutMatch.sameSession(span(0, 50), span(65, 90)))  // 15 min gap
    }

    @Test func pairsPickBestOverlapAndUseEachOnce() {
        let hevy = [span(0, 50), span(300, 340)]
        let health = [span(45, 60), span(2, 52), span(305, 345)]
        let p = WorkoutMatch.pairs(hevy: hevy, health: health)
        #expect(p.map { $0.0 } == [0, 1])
        #expect(p.map { $0.1 } == [1, 2])
    }

    @Test func promptRules() {
        let now = t0.addingTimeInterval(3 * 3600)
        let w = Workout(kind: .strength, start: t0, durationSec: 50 * 60)
        #expect(WorkoutPrompt.shouldAsk(w, now: now, enabled: true, paused: false))
        #expect(!WorkoutPrompt.shouldAsk(w, now: now, enabled: true, paused: true))
        #expect(!WorkoutPrompt.shouldAsk(w, now: now, enabled: false, paused: false))
        #expect(!WorkoutPrompt.shouldAsk(w, now: t0.addingTimeInterval(30 * 3600), enabled: true, paused: false))
        w.promptedAt = now
        #expect(!WorkoutPrompt.shouldAsk(w, now: now, enabled: true, paused: false))
        let short = Workout(kind: .walk, start: t0, durationSec: 6 * 60)
        #expect(!WorkoutPrompt.shouldAsk(short, now: now, enabled: true, paused: false))
        let strava = Workout(kind: .run, start: t0, durationSec: 40 * 60)
        strava.aiEligible = false
        #expect(!WorkoutPrompt.shouldAsk(strava, now: now, enabled: true, paused: false))
    }

    @Test func promptSettings() {
        let now = t0.addingTimeInterval(3 * 3600)
        let w = Workout(kind: .strength, start: t0, durationSec: 15 * 60)
        #expect(!WorkoutPrompt.shouldAsk(w, now: now, enabled: true, paused: false, minMinutes: 20))
        #expect(WorkoutPrompt.shouldAsk(w, now: now, enabled: true, paused: false, minMinutes: 10))
        #expect(!WorkoutPrompt.shouldAsk(w, now: now, enabled: true, paused: false, minMinutes: 0, hevyHasEffort: true))
        #expect(WorkoutPrompt.shouldAsk(w, now: now, enabled: true, paused: false, minMinutes: 0, hevyHasEffort: true, skipIfHevyEffort: false))
        #expect(WorkoutPrompt.delay(w, now: w.end, waitMinutes: 10) == 600)
        #expect(WorkoutPrompt.delay(w, now: w.end.addingTimeInterval(3600), waitMinutes: 10) == 1)
    }

    static let workoutsJSON = """
    {"page":1,"page_count":2,"workouts":[{"id":"w1","title":"[synthetic] Upper","description":"",
     "start_time":"2026-10-30T09:00:00Z","end_time":"2026-10-30T09:52:00.000Z",
     "updated_at":"2026-10-30T10:00:00Z","created_at":"2026-10-30T10:00:00Z",
     "exercises":[{"index":0,"title":"Bench Press","notes":"","exercise_template_id":"x","superset_id":null,
       "sets":[{"index":0,"type":"warmup","weight_kg":100,"reps":10,"distance_meters":null,"duration_seconds":null,"rpe":null},
               {"index":1,"type":"normal","weight_kg":40,"reps":8,"distance_meters":null,"duration_seconds":null,"rpe":8}]},
       {"index":1,"title":"Row","notes":"","exercise_template_id":"y","superset_id":null,
       "sets":[{"index":0,"type":"normal","weight_kg":42.5,"reps":10,"distance_meters":null,"duration_seconds":null,"rpe":null}]}]}]}
    """

    @Test func decodesWorkoutsAndTopSet() throws {
        let (ws, count) = try HevyAPI.decodeWorkouts(Data(Self.workoutsJSON.utf8))
        #expect(count == 2)
        #expect(ws.count == 1)
        #expect(ws[0].exercises.count == 2)
        #expect(ws[0].end_time.timeIntervalSince(ws[0].start_time) == 52 * 60)
        // The warm-up at 100 kg is ignored.
        #expect(ws[0].topSet == "Row 42.5 kg × 10")
    }

    @Test func decodesEvents() throws {
        let json = """
        {"page":1,"page_count":1,"events":[
          {"type":"deleted","id":"w9","deleted_at":"2026-10-30T10:00:00Z"},
          {"type":"updated","workout":{"id":"w2","title":"[synthetic]","start_time":"2026-10-29T09:00:00Z","end_time":"2026-10-29T10:00:00Z","exercises":[]}}]}
        """
        let (es, _) = try HevyAPI.decodeEvents(Data(json.utf8))
        #expect(es.count == 2)
        #expect(es[0] == .deleted(id: "w9"))
        if case .updated(let w) = es[1] { #expect(w.id == "w2") } else { Issue.record("expected update") }
    }
}
