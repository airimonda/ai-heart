# 02 Data model (SwiftData)

Store with `.complete` file protection. Exclude from iCloud backup by default (trade-off: lose the phone, lose the data; the owner can export). All timestamps are stored with a timezone identifier. A "day" is anchored to the sleep-wake cycle, not midnight.

```
Entry
  id, createdAt, tz
  kind: photo | feeling | body | write | voice | workoutNote | bodyCheck
  valence: Float?     // -1...1  unpleasant to pleasant
  arousal: Float?     // -1...1  still to stirred
  word: String?       // chosen or own word
  bodyRegions: [String]; sensations: [String]
  text: String?; audioPath: String?; photoPath: String?   // photos live in the app sandbox, not the Camera Roll
  status: kept | resting | released
  decidedBy: auto | user
  restUntil: Date?; releasedAt: Date?
  keptLines: [String]  // only for let-go entries
  keepNumbers: Bool    // default true
  embeddingId: UUID?   // deleted on release

DaySummary            // derived from HealthKit, one per anchored day
  day, tz, sleepMin, sleepStages, restingHR, hrvSDNN, respRate, wristTempDelta,
  steps, activeKcal, totalKcal, exerciseMin, cycleDay?, phase?, lifeEventIds

Workout
  id, source: healthkit | hevy | strava, externalId, type, start, durationSec,
  activeKcal, avgHR, rpe?, focus?, note?, aiEligible: Bool   // strava => false
HevySet               // from Hevy only
  workoutId, exerciseName, setType, weightKg, reps, rpe?

Cycle                 // derived
  id, startDate, endDate?, lengthDays?, ovulationEstimate?, method: flow | temp | calendar
MedicationLog
  id, medicationRef, takenAt, source: healthkit | manual
LabResult            // one marker from one report, manual or imported
  date, marker (code), value?, unit?, low?, high?, note?, reportId? (groups one report)
DoseChange
  date, fromText, toText
BodyCheck            // weekly body check-in
  weekStart, signs: [String: Int]   // 0 none, 1 some, 2 a lot
  tookAsUsual: yes | mostly | no
Forecast
  madeAt, targetDay, horizon, valenceMu, arousalMu, sigma, modelVersion, features
ForecastEval
  forecastId, actualValence?, actualArousal?, baselineError, modelError

LifeEvent             // move, travel, other; resets baselines and marks charts
  date, kind, label
QuietTopic            // terms the LLM never raises or searches
  term
AboutMe               // single encrypted document, user editable
  markdown, updatedAt
Settings              // pace, resurfacing=false, pause, restDays, decideAuto, outlook on/off, uses cycle/labs/training
ConnectionState       // provider, status, lastSync, tokens live in Keychain, never here
```

`ListenSession` is not stored. Only what she chooses to keep becomes an `Entry`.

## Sync fields (on every syncable model)
`syncId: UUID`, `updatedAt: Date`, `deviceId: String`. On `Entry` also `stateVersion: Int` and `stateChangedAt: Date`. Add `PurgeRecord { entryId, purgedAt }` (a tombstone with no content). Attributes holding personal content are `@Attribute(.allowsCloudEncryption)`. See `docs/11`.

Units: store SI (kg, meters, kcal, bpm, ms). Convert in the UI.
Retention: DaySummary and Workout are recomputable from sources and may be rebuilt. Entries are the only irreplaceable data.
