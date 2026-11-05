import Foundation
import SwiftData

// CloudKit-compatible from the first commit (docs/11):
// every attribute optional or defaulted, no unique constraints, no .deny delete rules.
// Personal content is marked .allowsCloudEncryption. Ids, timestamps and status stay plain.
// DECIDE (owner): confirm this encrypted set before the first production CloudKit deploy.

public enum EntryKind: String, Codable, CaseIterable, Sendable {
    case photo, feeling, body, write, voice, workoutNote, bodyCheck
}

public enum EntryStatus: String, Codable, Sendable {
    case kept, resting, released
}

public enum DecidedBy: String, Codable, Sendable {
    case auto, user
}

@Model
public final class Entry {
    // Sync fields
    public var syncId: UUID = UUID()
    public var updatedAt: Date = Date()
    public var deviceId: String = ""
    public var stateVersion: Int = 0
    public var stateChangedAt: Date = Date()

    public var createdAt: Date = Date()
    public var tz: String = TimeZone.current.identifier
    public var kindRaw: String = EntryKind.feeling.rawValue

    @Attribute(.allowsCloudEncryption) public var valence: Double?
    @Attribute(.allowsCloudEncryption) public var arousal: Double?
    /// The on-device model's guess at the entry's tone, for color only (owner, 2026-11-01).
    /// Never used for statistics, the outlook or patterns: those use her own mood point.
    @Attribute(.allowsCloudEncryption) public var toneValence: Double?
    @Attribute(.allowsCloudEncryption) public var toneArousal: Double?
    /// True when valence/arousal were guessed by the on-device model from her writing because she
    /// wrote at length and did not tap a mood point (owner, 2026-11-04). Shown as a guess she can fix;
    /// counts in charts, never in outlook training. Her tap or "Fits" sets it back to false.
    public var moodGuessed: Bool = false
    @Attribute(.allowsCloudEncryption) public var word: String?
    @Attribute(.allowsCloudEncryption) public var bodyRegions: [String] = []
    @Attribute(.allowsCloudEncryption) public var sensations: [String] = []
    @Attribute(.allowsCloudEncryption) public var text: String?

    // Photos and audio live in the store (external storage), never in the Camera Roll.
    // docs/09 #9: verify CloudKit asset encryption; if not covered, encrypt the bytes ourselves.
    @Attribute(.externalStorage) public var photoData: Data?
    @Attribute(.externalStorage) public var thumbData: Data?
    @Attribute(.externalStorage) public var audioData: Data?
    public var audioSeconds: Double?

    public var statusRaw: String = EntryStatus.kept.rawValue
    public var decidedByRaw: String = DecidedBy.user.rawValue
    public var restUntil: Date?
    public var releasedAt: Date?
    @Attribute(.allowsCloudEncryption) public var keptLines: [String] = []
    /// Notes kept from a let-go entry, as JSON (`ReleaseNote`). Optional for CloudKit.
    @Attribute(.allowsCloudEncryption) public var releaseNoteJSON: String?
    public var keepNumbers: Bool = true
    public var embeddingId: UUID?

    public init(kind: EntryKind, createdAt: Date = Date(), timeZone: TimeZone = .current) {
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.tz = timeZone.identifier
        self.updatedAt = createdAt
        self.stateChangedAt = createdAt
    }

    public var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .feeling }
        set { kindRaw = newValue.rawValue }
    }

    public var status: EntryStatus {
        get { EntryStatus(rawValue: statusRaw) ?? .kept }
        set { statusRaw = newValue.rawValue }
    }

    public var releaseNote: ReleaseNote? {
        get { ReleaseNote.decode(releaseNoteJSON) }
        // A let-go entry keeps only the summary of its note, never her exact lines (owner, 2026-11-05).
        set { releaseNoteJSON = (status == .kept ? newValue : newValue?.summary)?.encoded() }
    }

    public var decidedBy: DecidedBy {
        get { DecidedBy(rawValue: decidedByRaw) ?? .user }
        set { decidedByRaw = newValue.rawValue }
    }

    public var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }

    /// First line of her writing, used as a caption.
    public var caption: String? {
        guard let text, !text.isEmpty else { return nil }
        return text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
    }
}

/// Tombstone for a purged entry. No content. Always beats a stale copy (docs/11).
@Model
public final class PurgeRecord {
    public var entryId: UUID = UUID()
    public var purgedAt: Date = Date()

    public init(entryId: UUID, purgedAt: Date = Date()) {
        self.entryId = entryId
        self.purgedAt = purgedAt
    }
}

public enum LookBackPace: String, Codable, CaseIterable, Sendable {
    case weekly, monthly, onRequest
}

/// Single row. Uniqueness is enforced in code, not by a constraint.
@Model
public final class AppSettings {
    public var syncId: UUID = UUID()
    public var updatedAt: Date = Date()
    public var paceRaw: String = LookBackPace.weekly.rawValue
    public var resurfacing: Bool = false
    public var pauseEverything: Bool = false
    public var restDays: Int = 7
    public var decideAuto: Bool = true
    /// Keep the mood point and body map of a let-go entry (docs/03 #5).
    public var keepNumbers: Bool = true
    public var outlookOn: Bool = true
    public var usesCycle: Bool = true
    public var usesLabs: Bool = true
    public var usesTraining: Bool = true
    public var faceIDLock: Bool = false
    /// One prompt per new workout for effort, focus and a note (docs/08 M5).
    public var askToRateWorkouts: Bool = true
    /// Workout rating (design: WorkoutRating): minutes to wait after a workout ends,
    /// shortest workout worth asking about, and skip when Hevy already logged effort.
    public var rateWaitMinutes: Int = 10
    public var rateMinMinutes: Int = 20
    public var rateSkipIfHevyEffort: Bool = true
    /// Reminder to write, set by her (owner, 2026-10-31). Off until she turns it on.
    public var reminderOn: Bool = false
    public var reminderHour: Int = 21
    public var reminderMinute: Int = 0
    /// Calendar weekdays, 1 = Sunday ... 7 = Saturday.
    public var reminderDays: [Int] = [1, 2, 3, 4, 5, 6, 7]
    public var reminderSkipIfWritten: Bool = true
    /// A small weekly card on Now asking how the app is working (owner, 2026-10-31).
    public var askForAppFeedback: Bool = true
    /// The day starts at this hour until sleep data can anchor it (docs/02).
    public var dayStartHour: Int = 4
    /// Static text she writes herself. Never generated.
    @Attribute(.allowsCloudEncryption) public var safetyPage: String = ""
    /// Listen (docs/13): when it may speak up on its own ("ask", "sometimes", "often"), read replies
    /// aloud, one gentle line after a long session, and offer a person from her Safety page.
    public var listenOffersRaw: String = ListenOffers.ask.rawValue
    public var listenSpeak: Bool = false
    public var listenLongNote: Bool = false
    public var listenOfferPerson: Bool = false
    /// Notes from a steady day (docs/15): what she wants to hear when it is fast, heavy, looping or
    /// too much, and the early signs she knows in herself. Written by her, never generated.
    @Attribute(.allowsCloudEncryption) public var steadyFast: String = ""
    @Attribute(.allowsCloudEncryption) public var steadyHeavy: String = ""
    @Attribute(.allowsCloudEncryption) public var steadyLoop: String = ""
    @Attribute(.allowsCloudEncryption) public var steadyFlooded: String = ""
    @Attribute(.allowsCloudEncryption) public var steadySigns: String = ""
    /// "When I go quiet" (docs/15): one non-demanding check-in after a gap longer than her usual one.
    /// On because she asked for it; she can turn it off.
    public var quietCheckOn: Bool = true
    /// Safety plan in the six steps of the Stanley-Brown safety planning intervention (docs/17).
    /// Written by her, never generated. `safetyPage` stays as "Anything else".
    @Attribute(.allowsCloudEncryption) public var planSigns: String = ""
    @Attribute(.allowsCloudEncryption) public var planCoping: String = ""
    @Attribute(.allowsCloudEncryption) public var planPlaces: String = ""
    @Attribute(.allowsCloudEncryption) public var planHelpers: String = ""
    @Attribute(.allowsCloudEncryption) public var planPros: String = ""
    @Attribute(.allowsCloudEncryption) public var planSafeSpace: String = ""
    /// Her own early-warning signs, one per line, written with her clinician (docs/17). The app
    /// watches only for the ones it can see (sleep, her taps) and describes, never labels.
    @Attribute(.allowsCloudEncryption) public var warningSigns: [String] = []
    public var watchSigns: Bool = true
    /// Day ordinal of the last "your signs" card, so it shows at most once per stretch.
    public var signsNoticedDay: Int = 0
    /// Let-go asks first: a hard entry is offered for letting go, she holds to confirm (docs/17).
    public var releaseAsks: Bool = true
    /// On-device model she picked (docs/17): "gemma-4-e2b" or "qwen3-vl-4b".
    public var modelChoice: String = "qwen3-vl-4b"

    public init() {}

    public var listenOffers: ListenOffers {
        get { ListenOffers(rawValue: listenOffersRaw) ?? .ask }
        set { listenOffersRaw = newValue.rawValue }
    }

    public var pace: LookBackPace {
        get { LookBackPace(rawValue: paceRaw) ?? .weekly }
        set { paceRaw = newValue.rawValue }
    }
}

/// Terms the model never raises or searches. Also hidden from journal search.
@Model
public final class QuietTopic {
    public var syncId: UUID = UUID()
    public var updatedAt: Date = Date()
    @Attribute(.allowsCloudEncryption) public var term: String = ""

    public init(term: String) { self.term = term }
}

/// Single encrypted document she edits. Imported once from the private seed (later milestone).
@Model
public final class AboutMe {
    public var syncId: UUID = UUID()
    public var updatedAt: Date = Date()
    @Attribute(.allowsCloudEncryption) public var markdown: String = ""

    public init(markdown: String = "") { self.markdown = markdown }
}

public enum LifeEventKind: String, Codable, Sendable { case move, travel, other }

/// Resets baselines and marks charts.
@Model
public final class LifeEvent {
    public var syncId: UUID = UUID()
    public var updatedAt: Date = Date()
    public var date: Date = Date()
    public var kindRaw: String = LifeEventKind.other.rawValue
    @Attribute(.allowsCloudEncryption) public var label: String = ""

    public init(date: Date, kind: LifeEventKind, label: String) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.label = label
    }
}

/// Her own words from one "Talk it through" conversation (owner, 2026-11-04: "a memory, not a
/// personality, just a mirror"; docs/21). Only what she wrote, never the app's replies. Searched on the
/// phone so a later conversation can mirror her words back ("last time you said ..."). She can forget
/// any one, or all.
@Model
public final class TalkMemory {
    public var syncId: UUID = UUID()
    public var updatedAt: Date = Date()
    public var date: Date = Date()
    @Attribute(.allowsCloudEncryption) public var text: String = ""
    public var deviceId: String = ""

    public init(date: Date = Date(), text: String, deviceId: String = "") {
        self.date = date; self.text = text; self.deviceId = deviceId; self.updatedAt = date
    }
}

public enum AiHeartSchema {
    public static let models: [any PersistentModel.Type] = [
        Entry.self, PurgeRecord.self, AppSettings.self, QuietTopic.self, AboutMe.self, LifeEvent.self, DaySummary.self, Workout.self, HevySet.self,
        BodyCheck.self, LabResult.self, DoseChange.self, MedicationLog.self,
        GuessFeedback.self, AppFeedback.self, ExportRecord.self, ListenSession.self, MediaItem.self, AppOpen.self, TechniqueTry.self,
        TalkMemory.self, DeletedEntry.self,
    ]
}
