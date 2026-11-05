import CommonCrypto
import CryptoKit
import Foundation
import SwiftData

// Encrypted backup (M11, docs/05). "Everything, encrypted": a ZIP of JSON (and media files)
// sealed with AES-GCM under a key derived from a passphrase she chooses. Nothing leaves the
// device except where she sends the file. Released entries are never included.

public enum BackupError: Error, Equatable {
    case wrongPassphrase
    case notABackup
    case emptyPassphrase
    case unsupportedVersion(Int)
    case keyDerivationFailed
}

public enum BackupCrypto {
    static let magic = Data("AIHEART1".utf8)
    static let saltLength = 16
    public static let defaultIterations = 600_000
    static let maxIterations: UInt32 = 10_000_000
    /// magic + salt + iterations + (nonce 12 + tag 16)
    static let headerLength = 8 + 16 + 4

    public static func seal(_ plain: Data, passphrase: String) throws -> Data {
        try seal(plain, passphrase: passphrase, iterations: defaultIterations)
    }

    public static func open(_ sealed: Data, passphrase: String) throws -> Data {
        guard sealed.count >= headerLength + 28, sealed.prefix(8) == magic else { throw BackupError.notABackup }
        let bytes = [UInt8](sealed)
        let salt = Data(bytes[8..<24])
        let iterations = bytes[24..<28].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard iterations > 0, iterations <= maxIterations else { throw BackupError.notABackup }
        guard !passphrase.isEmpty else { throw BackupError.emptyPassphrase }
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let header = Data(bytes[0..<headerLength])
        do {
            let box = try AES.GCM.SealedBox(combined: Data(bytes[headerLength...]))
            return try AES.GCM.open(box, using: key, authenticating: header)
        } catch {
            // GCM cannot tell a wrong passphrase from a damaged file; report the likelier one.
            throw BackupError.wrongPassphrase
        }
    }

    /// Internal so tests can use few iterations. The count is stored in the file, so `open` needs no parameter.
    static func seal(_ plain: Data, passphrase: String, iterations: Int) throws -> Data {
        guard !passphrase.isEmpty else { throw BackupError.emptyPassphrase }
        var salt = Data(count: saltLength)
        var rng = SystemRandomNumberGenerator()
        for i in 0..<saltLength { salt[i] = UInt8.random(in: 0...255, using: &rng) }
        let n = UInt32(iterations)
        var header = magic
        header.append(salt)
        for shift in [24, 16, 8, 0] { header.append(UInt8((n >> UInt32(shift)) & 0xFF)) }
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: n)
        let box = try AES.GCM.seal(plain, using: key, authenticating: header)
        guard let combined = box.combined else { throw BackupError.keyDerivationFailed }
        return header + combined
    }

    static func deriveKey(passphrase: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        // NFC, so the same words typed on another keyboard give the same key.
        let pass = Array(passphrase.precomposedStringWithCanonicalMapping.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = pass.withUnsafeBufferPointer { p in
            salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    UnsafeRawPointer(p.baseAddress!).assumingMemoryBound(to: Int8.self), pass.count,
                    s.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                    &derived, derived.count)
            }
        }
        guard status == kCCSuccess else { throw BackupError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }
}

/// A line in the on-device export log (docs/05). Kind, range and date only; never contents.
@Model
public final class ExportRecord {
    public var syncId: UUID = UUID()
    public var date: Date = Date()
    /// "report", "spreadsheet", "backup", "therapist" or "doctor".
    public var kind: String = ""
    public var rangeText: String = ""
    public var deviceId: String = ""

    public init(kind: String, rangeText: String, deviceId: String = "", date: Date = Date()) {
        self.kind = kind
        self.rangeText = rangeText
        self.deviceId = deviceId
        self.date = date
    }
}

public struct RestoreSummary: Equatable {
    /// Rows added, by model name ("Entry", "Workout", ...). Only types with at least one row appear.
    public var added: [String: Int]
    /// Rows left alone: already here, or blocked by a tombstone.
    public var skipped: Int

    public init(added: [String: Int] = [:], skipped: Int = 0) {
        self.added = added
        self.skipped = skipped
    }
}

public enum BackupArchive {
    /// 2: labs are one row per marker (labResults.json) and the weekly check is bodyChecks.json.
    public static let formatVersion = 2
    /// Rows from sample (demo) data carry this device id and are never exported.
    public static let demoDeviceId = "demo"

    // MARK: DTOs (one per model, every persisted attribute)

    struct Manifest: Codable {
        var format: Int
        var created: Date
        var counts: [String: Int]
    }

    struct EntryDTO: Codable, Equatable {
        var syncId: UUID, updatedAt: Date, deviceId: String, stateVersion: Int, stateChangedAt: Date
        var createdAt: Date, tz: String, kindRaw: String
        var valence: Double?, arousal: Double?, word: String?
        var toneValence: Double?, toneArousal: Double?
        var bodyRegions: [String], sensations: [String], text: String?
        var audioSeconds: Double?
        var statusRaw: String, decidedByRaw: String, restUntil: Date?, releasedAt: Date?
        var keptLines: [String], keepNumbers: Bool, embeddingId: UUID?
        var releaseNoteJSON: String? = nil
        var moodGuessed: Bool? = nil
    }

    struct PurgeDTO: Codable, Equatable { var entryId: UUID, purgedAt: Date }

    struct SettingsDTO: Codable, Equatable {
        var syncId: UUID, updatedAt: Date, paceRaw: String
        var resurfacing: Bool, pauseEverything: Bool, restDays: Int, decideAuto: Bool, keepNumbers: Bool
        var outlookOn: Bool, usesCycle: Bool, usesLabs: Bool, usesTraining: Bool, faceIDLock: Bool
        var askToRateWorkouts: Bool, rateWaitMinutes: Int, rateMinMinutes: Int, rateSkipIfHevyEffort: Bool
        var reminderOn: Bool, reminderHour: Int, reminderMinute: Int, reminderDays: [Int], reminderSkipIfWritten: Bool
        var askForAppFeedback: Bool, dayStartHour: Int, safetyPage: String
        // Added with Listen (M17). Optional so a backup made before it still restores.
        var listenOffersRaw: String?, listenSpeak: Bool?, listenLongNote: Bool?, listenOfferPerson: Bool?
        // Added with hard moments (docs/15). Optional for older backups.
        var steadyFast: String? = nil, steadyHeavy: String? = nil, steadyLoop: String? = nil
        var steadyFlooded: String? = nil, steadySigns: String? = nil, quietCheckOn: Bool? = nil
        // Added with the safety plan, early signs, ask-first release and model choice (docs/17).
        var planSigns: String? = nil, planCoping: String? = nil, planPlaces: String? = nil
        var planHelpers: String? = nil, planPros: String? = nil, planSafeSpace: String? = nil
        var warningSigns: [String]? = nil, watchSigns: Bool? = nil, signsNoticedDay: Int? = nil
        var releaseAsks: Bool? = nil, modelChoice: String? = nil
    }

    /// One entry's fields, as stored in a backup or in Recently deleted.
    static func dto(_ e: Entry) -> EntryDTO {
        EntryDTO(syncId: e.syncId, updatedAt: e.updatedAt, deviceId: e.deviceId, stateVersion: e.stateVersion, stateChangedAt: e.stateChangedAt,
                 createdAt: e.createdAt, tz: e.tz, kindRaw: e.kindRaw, valence: e.valence, arousal: e.arousal, word: e.word,
                 toneValence: e.toneValence, toneArousal: e.toneArousal, bodyRegions: e.bodyRegions, sensations: e.sensations, text: e.text,
                 audioSeconds: e.audioSeconds, statusRaw: e.statusRaw, decidedByRaw: e.decidedByRaw, restUntil: e.restUntil,
                 releasedAt: e.releasedAt, keptLines: e.keptLines, keepNumbers: e.keepNumbers, embeddingId: e.embeddingId,
                 releaseNoteJSON: e.releaseNoteJSON, moodGuessed: e.moodGuessed)
    }

    /// Rebuilds an entry from its stored fields.
    static func entry(from d: EntryDTO, photo: Data?, thumb: Data?, audio: Data?) -> Entry {
        let e = Entry(kind: .feeling, createdAt: d.createdAt, timeZone: TimeZone(identifier: d.tz) ?? .current)
        e.syncId = d.syncId; e.updatedAt = d.updatedAt; e.deviceId = d.deviceId
        e.stateVersion = d.stateVersion; e.stateChangedAt = d.stateChangedAt
        e.tz = d.tz; e.kindRaw = d.kindRaw
        e.valence = d.valence; e.arousal = d.arousal; e.word = d.word
        e.toneValence = d.toneValence; e.toneArousal = d.toneArousal
        e.bodyRegions = d.bodyRegions; e.sensations = d.sensations; e.text = d.text
        e.photoData = photo; e.thumbData = thumb; e.audioData = audio
        e.audioSeconds = d.audioSeconds
        e.statusRaw = d.statusRaw; e.decidedByRaw = d.decidedByRaw
        e.restUntil = d.restUntil; e.releasedAt = d.releasedAt
        e.keptLines = d.keptLines; e.keepNumbers = d.keepNumbers; e.embeddingId = d.embeddingId
        e.releaseNoteJSON = d.releaseNoteJSON
        e.moodGuessed = d.moodGuessed ?? false
        return e
    }

    struct DeletedEntryDTO: Codable, Equatable {
        var syncId: UUID, entryId: UUID, deletedAt: Date, createdAt: Date, payload: Data, preview: String
    }

    struct TalkMemoryDTO: Codable, Equatable {
        var syncId: UUID, updatedAt: Date, date: Date, text: String, deviceId: String
    }

    struct TechniqueTryDTO: Codable, Equatable {
        var syncId: UUID, date: Date, techniqueId: String, stateRaw: String, before: Int?, after: Int?, deviceId: String
    }

    struct QuietTopicDTO: Codable, Equatable { var syncId: UUID, updatedAt: Date, term: String }
    struct AboutMeDTO: Codable, Equatable { var syncId: UUID, updatedAt: Date, markdown: String }
    struct LifeEventDTO: Codable, Equatable { var syncId: UUID, updatedAt: Date, date: Date, kindRaw: String, label: String }

    struct DayDTO: Codable, Equatable {
        var syncId: UUID, updatedAt: Date, deviceId: String, dayKey: String, tz: String
        var sleepMin: Double?, sleepDeepMin: Double?, sleepRemMin: Double?, sleepCoreMin: Double?, awakeMin: Double?
        var sleepSourceRaw: String?, bedtime: Date?, wakeTime: Date?, rested: Int?
        var restingHR: Double?, manualHR: Double?, weightKg: Double?, systolic: Double?, diastolic: Double?
        var warningSigns: [String]
        var hrvSDNN: Double?, respRate: Double?, wristTempC: Double?, steps: Double?
        var activeKcal: Double?, basalKcal: Double?, exerciseMin: Double?
        var menstrualFlow: Int?, cycleDay: Int?, phaseRaw: String?
    }

    struct WorkoutDTO: Codable, Equatable {
        var syncId: UUID, updatedAt: Date, deviceId: String
        var healthId: String?, hevyId: String?, kindRaw: String, title: String?
        var start: Date, durationSec: Double, activeKcal: Double?, avgHR: Double?
        var rpe: Int?, focusRaw: String?, note: String?, ratedAt: Date?, promptedAt: Date?, aiEligible: Bool
    }

    struct HevySetDTO: Codable, Equatable {
        var syncId: UUID, hevyWorkoutId: String, exerciseIndex: Int, exerciseName: String, setIndex: Int, setType: String
        var weightKg: Double?, reps: Int?, rpe: Double?, distanceM: Double?, durationSec: Double?
    }

    struct BodyCheckDTO: Codable, Equatable {
        var syncId: UUID, updatedAt: Date, deviceId: String, weekKey: String
        var signs: [String: Int], tookAsUsualRaw: String?
    }

    struct LabResultDTO: Codable, Equatable {
        var syncId: UUID, updatedAt: Date, deviceId: String, date: Date
        var marker: String, value: Double?, unit: String?, low: Double?, high: Double?, note: String?
        var sourceRaw: String, labRegionRaw: String?, reportId: UUID?
    }

    struct DoseChangeDTO: Codable, Equatable {
        var syncId: UUID, updatedAt: Date, deviceId: String, date: Date, fromText: String, toText: String
    }

    struct MedicationLogDTO: Codable, Equatable {
        var syncId: UUID, updatedAt: Date, deviceId: String, medicationRef: String, takenAt: Date, sourceRaw: String, with: [String]
    }

    struct GuessFeedbackDTO: Codable, Equatable {
        var syncId: UUID, updatedAt: Date, deviceId: String, kind: String, dayKey: String
        var guess: String?, fit: Bool?, shown: [String], picked: String?
    }

    struct AppFeedbackDTO: Codable, Equatable { var syncId: UUID, createdAt: Date, text: String, mood: String? }

    struct ExportRecordDTO: Codable, Equatable { var syncId: UUID, date: Date, kind: String, rangeText: String, deviceId: String }

    struct ListenSessionDTO: Codable, Equatable {
        var syncId: UUID, date: Date, seconds: Double, offerRaw: String?, helpedRaw: String?, deviceId: String
    }

    struct AppOpenDTO: Codable, Equatable { var syncId: UUID, appName: String, date: Date, deviceId: String }

    struct MediaItemDTO: Codable, Equatable {
        var syncId: UUID, sourceRaw: String, title: String, creator: String?, startedAt: Date
        var durationSec: Double?, aiEligible: Bool, dedupeKey: String, deviceId: String
        var artistIds: String?, genres: String?
    }

    // MARK: File names

    enum File {
        static let manifest = "manifest.json"
        static let entries = "entries.json"
        static let purgeRecords = "purgeRecords.json"
        static let appSettings = "appSettings.json"
        static let quietTopics = "quietTopics.json"
        static let aboutMe = "aboutMe.json"
        static let lifeEvents = "lifeEvents.json"
        static let daySummaries = "daySummaries.json"
        static let workouts = "workouts.json"
        static let hevySets = "hevySets.json"
        static let bodyChecks = "bodyChecks.json"
        static let labResults = "labResults.json"
        static let doseChanges = "doseChanges.json"
        static let medicationLogs = "medicationLogs.json"
        static let guessFeedback = "guessFeedback.json"
        static let appFeedback = "appFeedback.json"
        static let exportRecords = "exportRecords.json"
        static let listenSessions = "listenSessions.json"
        static let techniqueTries = "techniqueTries.json"
        static let talkMemories = "talkMemories.json"
        static let deletedEntries = "deletedEntries.json"
        static let mediaItems = "mediaItems.json"
        static let appOpens = "appOpens.json"
    }

    static func mediaPath(_ id: UUID, _ kind: String) -> String {
        let ext = kind.hasSuffix("audio") ? "m4a" : "jpg"
        return "media/\(id.uuidString)-\(kind).\(ext)"
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }

    // MARK: Make

    public static func make(context: ModelContext) throws -> Data {
        let enc = encoder()
        var zip = ZipWriter()
        var counts: [String: Int] = [:]

        func put<D: Encodable>(_ file: String, _ name: String, _ dtos: [D]) throws {
            counts[name] = dtos.count
            zip.add(file, try enc.encode(dtos))
        }
        func rows<M: PersistentModel>(_ type: M.Type) throws -> [M] { try context.fetch(FetchDescriptor<M>()) }
        func notDemo(_ id: String) -> Bool { id != demoDeviceId }

        // Entries (released ones are not included; their tombstones are)
        let entries = try rows(Entry.self)
            .filter { notDemo($0.deviceId) && $0.status != .released }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
        var entryDTOs: [EntryDTO] = []
        for e in entries {
            entryDTOs.append(EntryDTO(
                syncId: e.syncId, updatedAt: e.updatedAt, deviceId: e.deviceId, stateVersion: e.stateVersion, stateChangedAt: e.stateChangedAt,
                createdAt: e.createdAt, tz: e.tz, kindRaw: e.kindRaw, valence: e.valence, arousal: e.arousal, word: e.word, toneValence: e.toneValence, toneArousal: e.toneArousal,
                bodyRegions: e.bodyRegions, sensations: e.sensations, text: e.text, audioSeconds: e.audioSeconds,
                statusRaw: e.statusRaw, decidedByRaw: e.decidedByRaw, restUntil: e.restUntil, releasedAt: e.releasedAt,
                keptLines: e.keptLines, keepNumbers: e.keepNumbers, embeddingId: e.embeddingId,
                releaseNoteJSON: e.releaseNoteJSON, moodGuessed: e.moodGuessed))
            if let d = e.photoData { zip.add(mediaPath(e.syncId, "photo"), d) }
            if let d = e.thumbData { zip.add(mediaPath(e.syncId, "thumb"), d) }
            if let d = e.audioData { zip.add(mediaPath(e.syncId, "audio"), d) }
        }
        try put(File.entries, "Entry", entryDTOs)

        try put(File.purgeRecords, "PurgeRecord", try rows(PurgeRecord.self)
            .sorted { $0.entryId.uuidString < $1.entryId.uuidString }
            .map { PurgeDTO(entryId: $0.entryId, purgedAt: $0.purgedAt) })

        try put(File.appSettings, "AppSettings", try rows(AppSettings.self)
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { s in SettingsDTO(
                syncId: s.syncId, updatedAt: s.updatedAt, paceRaw: s.paceRaw, resurfacing: s.resurfacing,
                pauseEverything: s.pauseEverything, restDays: s.restDays, decideAuto: s.decideAuto, keepNumbers: s.keepNumbers,
                outlookOn: s.outlookOn, usesCycle: s.usesCycle, usesLabs: s.usesLabs, usesTraining: s.usesTraining,
                faceIDLock: s.faceIDLock, askToRateWorkouts: s.askToRateWorkouts, rateWaitMinutes: s.rateWaitMinutes,
                rateMinMinutes: s.rateMinMinutes, rateSkipIfHevyEffort: s.rateSkipIfHevyEffort, reminderOn: s.reminderOn,
                reminderHour: s.reminderHour, reminderMinute: s.reminderMinute, reminderDays: s.reminderDays,
                reminderSkipIfWritten: s.reminderSkipIfWritten, askForAppFeedback: s.askForAppFeedback,
                dayStartHour: s.dayStartHour, safetyPage: s.safetyPage,
                listenOffersRaw: s.listenOffersRaw, listenSpeak: s.listenSpeak, listenLongNote: s.listenLongNote,
                listenOfferPerson: s.listenOfferPerson, steadyFast: s.steadyFast, steadyHeavy: s.steadyHeavy,
                steadyLoop: s.steadyLoop, steadyFlooded: s.steadyFlooded, steadySigns: s.steadySigns, quietCheckOn: s.quietCheckOn,
                planSigns: s.planSigns, planCoping: s.planCoping, planPlaces: s.planPlaces, planHelpers: s.planHelpers,
                planPros: s.planPros, planSafeSpace: s.planSafeSpace, warningSigns: s.warningSigns, watchSigns: s.watchSigns,
                signsNoticedDay: s.signsNoticedDay, releaseAsks: s.releaseAsks, modelChoice: s.modelChoice) })

        try put(File.quietTopics, "QuietTopic", try rows(QuietTopic.self)
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { QuietTopicDTO(syncId: $0.syncId, updatedAt: $0.updatedAt, term: $0.term) })

        try put(File.aboutMe, "AboutMe", try rows(AboutMe.self)
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { AboutMeDTO(syncId: $0.syncId, updatedAt: $0.updatedAt, markdown: $0.markdown) })

        try put(File.lifeEvents, "LifeEvent", try rows(LifeEvent.self)
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { LifeEventDTO(syncId: $0.syncId, updatedAt: $0.updatedAt, date: $0.date, kindRaw: $0.kindRaw, label: $0.label) })

        try put(File.daySummaries, "DaySummary", try rows(DaySummary.self)
            .filter { notDemo($0.deviceId) }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { d in DayDTO(
                syncId: d.syncId, updatedAt: d.updatedAt, deviceId: d.deviceId, dayKey: d.dayKey, tz: d.tz,
                sleepMin: d.sleepMin, sleepDeepMin: d.sleepDeepMin, sleepRemMin: d.sleepRemMin, sleepCoreMin: d.sleepCoreMin,
                awakeMin: d.awakeMin, sleepSourceRaw: d.sleepSourceRaw, bedtime: d.bedtime, wakeTime: d.wakeTime, rested: d.rested,
                restingHR: d.restingHR, manualHR: d.manualHR, weightKg: d.weightKg, systolic: d.systolic, diastolic: d.diastolic,
                warningSigns: d.warningSigns, hrvSDNN: d.hrvSDNN, respRate: d.respRate, wristTempC: d.wristTempC, steps: d.steps,
                activeKcal: d.activeKcal, basalKcal: d.basalKcal, exerciseMin: d.exerciseMin, menstrualFlow: d.menstrualFlow,
                cycleDay: d.cycleDay, phaseRaw: d.phaseRaw) })

        let allWorkouts = try rows(Workout.self)
        let demoHevyIds = Set(allWorkouts.filter { !notDemo($0.deviceId) }.compactMap(\.hevyId))
        try put(File.workouts, "Workout", allWorkouts
            .filter { notDemo($0.deviceId) }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { w in WorkoutDTO(
                syncId: w.syncId, updatedAt: w.updatedAt, deviceId: w.deviceId, healthId: w.healthId, hevyId: w.hevyId,
                kindRaw: w.kindRaw, title: w.title, start: w.start, durationSec: w.durationSec, activeKcal: w.activeKcal,
                avgHR: w.avgHR, rpe: w.rpe, focusRaw: w.focusRaw, note: w.note, ratedAt: w.ratedAt, promptedAt: w.promptedAt,
                aiEligible: w.aiEligible) })

        try put(File.hevySets, "HevySet", try rows(HevySet.self)
            .filter { !demoHevyIds.contains($0.hevyWorkoutId) }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { s in HevySetDTO(
                syncId: s.syncId, hevyWorkoutId: s.hevyWorkoutId, exerciseIndex: s.exerciseIndex, exerciseName: s.exerciseName,
                setIndex: s.setIndex, setType: s.setType, weightKg: s.weightKg, reps: s.reps, rpe: s.rpe,
                distanceM: s.distanceM, durationSec: s.durationSec) })

        try put(File.bodyChecks, "BodyCheck", try rows(BodyCheck.self)
            .filter { notDemo($0.deviceId) }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { BodyCheckDTO(syncId: $0.syncId, updatedAt: $0.updatedAt, deviceId: $0.deviceId, weekKey: $0.weekKey,
                                signs: $0.signs, tookAsUsualRaw: $0.tookAsUsualRaw) })

        try put(File.labResults, "LabResult", try rows(LabResult.self)
            .filter { notDemo($0.deviceId) }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { l in LabResultDTO(
                syncId: l.syncId, updatedAt: l.updatedAt, deviceId: l.deviceId, date: l.date, marker: l.marker,
                value: l.value, unit: l.unit, low: l.low, high: l.high, note: l.note,
                sourceRaw: l.sourceRaw, labRegionRaw: l.labRegionRaw, reportId: l.reportId) })

        try put(File.doseChanges, "DoseChange", try rows(DoseChange.self)
            .filter { notDemo($0.deviceId) }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { DoseChangeDTO(syncId: $0.syncId, updatedAt: $0.updatedAt, deviceId: $0.deviceId, date: $0.date,
                                 fromText: $0.fromText, toText: $0.toText) })

        try put(File.medicationLogs, "MedicationLog", try rows(MedicationLog.self)
            .filter { notDemo($0.deviceId) }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { MedicationLogDTO(syncId: $0.syncId, updatedAt: $0.updatedAt, deviceId: $0.deviceId,
                                    medicationRef: $0.medicationRef, takenAt: $0.takenAt, sourceRaw: $0.sourceRaw, with: $0.with) })

        try put(File.guessFeedback, "GuessFeedback", try rows(GuessFeedback.self)
            .filter { notDemo($0.deviceId) }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { GuessFeedbackDTO(syncId: $0.syncId, updatedAt: $0.updatedAt, deviceId: $0.deviceId, kind: $0.kind,
                                    dayKey: $0.dayKey, guess: $0.guess, fit: $0.fit, shown: $0.shown, picked: $0.picked) })

        try put(File.appFeedback, "AppFeedback", try rows(AppFeedback.self)
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { AppFeedbackDTO(syncId: $0.syncId, createdAt: $0.createdAt, text: $0.text, mood: $0.mood) })

        try put(File.exportRecords, "ExportRecord", try rows(ExportRecord.self)
            .filter { notDemo($0.deviceId) }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { ExportRecordDTO(syncId: $0.syncId, date: $0.date, kind: $0.kind, rangeText: $0.rangeText, deviceId: $0.deviceId) })

        try put(File.listenSessions, "ListenSession", try rows(ListenSession.self)
            .filter { notDemo($0.deviceId) }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { ListenSessionDTO(syncId: $0.syncId, date: $0.date, seconds: $0.seconds, offerRaw: $0.offerRaw,
                                    helpedRaw: $0.helpedRaw, deviceId: $0.deviceId) })

        try put(File.techniqueTries, "TechniqueTry", try rows(TechniqueTry.self)
            .filter { notDemo($0.deviceId) }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { TechniqueTryDTO(syncId: $0.syncId, date: $0.date, techniqueId: $0.techniqueId, stateRaw: $0.stateRaw,
                                   before: $0.before, after: $0.after, deviceId: $0.deviceId) })

        try put(File.deletedEntries, "DeletedEntry", try rows(DeletedEntry.self)
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { d in
                if let p = d.photoData { zip.add(mediaPath(d.syncId, "deleted-photo"), p) }
                if let t = d.thumbData { zip.add(mediaPath(d.syncId, "deleted-thumb"), t) }
                if let a = d.audioData { zip.add(mediaPath(d.syncId, "deleted-audio"), a) }
                return DeletedEntryDTO(syncId: d.syncId, entryId: d.entryId, deletedAt: d.deletedAt, createdAt: d.createdAt,
                                       payload: d.payload, preview: d.preview)
            })

        try put(File.talkMemories, "TalkMemory", try rows(TalkMemory.self)
            .filter { notDemo($0.deviceId) }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { TalkMemoryDTO(syncId: $0.syncId, updatedAt: $0.updatedAt, date: $0.date, text: $0.text, deviceId: $0.deviceId) })

        try put(File.mediaItems, "MediaItem", try rows(MediaItem.self)
            .filter { notDemo($0.deviceId) }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { MediaItemDTO(syncId: $0.syncId, sourceRaw: $0.sourceRaw, title: $0.title, creator: $0.creator,
                                startedAt: $0.startedAt, durationSec: $0.durationSec, aiEligible: $0.aiEligible,
                                dedupeKey: $0.dedupeKey, deviceId: $0.deviceId, artistIds: $0.artistIds, genres: $0.genres) })

        try put(File.appOpens, "AppOpen", try rows(AppOpen.self)
            .filter { notDemo($0.deviceId) }
            .sorted { $0.syncId.uuidString < $1.syncId.uuidString }
            .map { AppOpenDTO(syncId: $0.syncId, appName: $0.appName, date: $0.date, deviceId: $0.deviceId) })

        zip.add(File.manifest, try enc.encode(Manifest(format: formatVersion, created: Date(), counts: counts)))
        return zip.finish()
    }

    // MARK: Restore

    /// Merges a backup into the store. Rows already here (same syncId) are left alone, an entry
    /// with a tombstone is never restored (CLAUDE.md #9), and settings are restored only if
    /// there are none. Saves once at the end; any error rolls everything back.
    /// After a restore, run `EntryLifecycle.runPurgeJob` so a tombstone from the backup also purges
    /// an older local copy of that entry.
    public static func restore(_ archive: Data, into context: ModelContext) throws -> RestoreSummary {
        let files: [String: Data]
        do { files = try ZipReader.entries(archive) } catch { throw BackupError.notABackup }
        guard let manifestData = files[File.manifest],
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData) else { throw BackupError.notABackup }
        guard manifest.format <= formatVersion else { throw BackupError.unsupportedVersion(manifest.format) }

        let dec = JSONDecoder()
        func list<D: Decodable>(_ file: String, _ type: D.Type) throws -> [D] {
            guard let data = files[file] else { return [] }
            do { return try dec.decode([D].self, from: data) } catch { throw BackupError.notABackup }
        }

        // Decode everything first, so a bad file fails before anything touches the context.
        let entries = try list(File.entries, EntryDTO.self)
        let purges = try list(File.purgeRecords, PurgeDTO.self)
        let settings = try list(File.appSettings, SettingsDTO.self)
        let topics = try list(File.quietTopics, QuietTopicDTO.self)
        let aboutMe = try list(File.aboutMe, AboutMeDTO.self)
        let events = try list(File.lifeEvents, LifeEventDTO.self)
        let days = try list(File.daySummaries, DayDTO.self)
        let workouts = try list(File.workouts, WorkoutDTO.self)
        let sets = try list(File.hevySets, HevySetDTO.self)
        let checks = try list(File.bodyChecks, BodyCheckDTO.self)
        let labs = try list(File.labResults, LabResultDTO.self)
        let doses = try list(File.doseChanges, DoseChangeDTO.self)
        let meds = try list(File.medicationLogs, MedicationLogDTO.self)
        let guesses = try list(File.guessFeedback, GuessFeedbackDTO.self)
        let notes = try list(File.appFeedback, AppFeedbackDTO.self)
        let exports = try list(File.exportRecords, ExportRecordDTO.self)
        let listens = try list(File.listenSessions, ListenSessionDTO.self)
        let tries = (try? list(File.techniqueTries, TechniqueTryDTO.self)) ?? []
        let talks = (try? list(File.talkMemories, TalkMemoryDTO.self)) ?? []
        let deleted = (try? list(File.deletedEntries, DeletedEntryDTO.self)) ?? []
        let media = try list(File.mediaItems, MediaItemDTO.self)
        let appOpens = (try? list(File.appOpens, AppOpenDTO.self)) ?? []

        func ids<M: PersistentModel>(_ type: M.Type, _ key: KeyPath<M, UUID>) throws -> Set<UUID> {
            var d = FetchDescriptor<M>()
            d.propertiesToFetch = [key]
            return Set(try context.fetch(d).map { $0[keyPath: key] })
        }

        var summary = RestoreSummary()
        func add(_ name: String) { summary.added[name, default: 0] += 1 }

        do {
            // Tombstones first: they decide which entries may come back.
            var tombstoned = try ids(PurgeRecord.self, \.entryId)
            for p in purges where !tombstoned.contains(p.entryId) {
                context.insert(PurgeRecord(entryId: p.entryId, purgedAt: p.purgedAt))
                tombstoned.insert(p.entryId)
                add("PurgeRecord")
            }
            summary.skipped += purges.count - (summary.added["PurgeRecord"] ?? 0)

            var have = try ids(Entry.self, \.syncId)
            for d in entries {
                if have.contains(d.syncId) || tombstoned.contains(d.syncId) || d.statusRaw == EntryStatus.released.rawValue {
                    summary.skipped += 1; continue
                }
                have.insert(d.syncId)
                let e = Entry(kind: .feeling, createdAt: d.createdAt, timeZone: TimeZone(identifier: d.tz) ?? .current)
                e.syncId = d.syncId; e.updatedAt = d.updatedAt; e.deviceId = d.deviceId
                e.stateVersion = d.stateVersion; e.stateChangedAt = d.stateChangedAt
                e.tz = d.tz; e.kindRaw = d.kindRaw
                e.valence = d.valence; e.arousal = d.arousal; e.word = d.word
                e.toneValence = d.toneValence; e.toneArousal = d.toneArousal
                e.bodyRegions = d.bodyRegions; e.sensations = d.sensations; e.text = d.text
                e.photoData = files[mediaPath(d.syncId, "photo")]
                e.thumbData = files[mediaPath(d.syncId, "thumb")]
                e.audioData = files[mediaPath(d.syncId, "audio")]
                e.audioSeconds = d.audioSeconds
                e.statusRaw = d.statusRaw; e.decidedByRaw = d.decidedByRaw
                e.restUntil = d.restUntil; e.releasedAt = d.releasedAt
                e.keptLines = d.keptLines; e.keepNumbers = d.keepNumbers; e.embeddingId = d.embeddingId
                e.releaseNoteJSON = d.releaseNoteJSON
                e.moodGuessed = d.moodGuessed ?? false
                context.insert(e)
                add("Entry")
            }

            // Settings are a single row: restore only when there is none.
            if try context.fetchCount(FetchDescriptor<AppSettings>()) == 0, let s = settings.first {
                let m = AppSettings()
                m.syncId = s.syncId; m.updatedAt = s.updatedAt; m.paceRaw = s.paceRaw
                m.resurfacing = s.resurfacing; m.pauseEverything = s.pauseEverything; m.restDays = s.restDays
                m.decideAuto = s.decideAuto; m.keepNumbers = s.keepNumbers; m.outlookOn = s.outlookOn
                m.usesCycle = s.usesCycle; m.usesLabs = s.usesLabs; m.usesTraining = s.usesTraining
                m.faceIDLock = s.faceIDLock; m.askToRateWorkouts = s.askToRateWorkouts
                m.rateWaitMinutes = s.rateWaitMinutes; m.rateMinMinutes = s.rateMinMinutes
                m.rateSkipIfHevyEffort = s.rateSkipIfHevyEffort
                m.reminderOn = s.reminderOn; m.reminderHour = s.reminderHour; m.reminderMinute = s.reminderMinute
                m.reminderDays = s.reminderDays; m.reminderSkipIfWritten = s.reminderSkipIfWritten
                m.askForAppFeedback = s.askForAppFeedback; m.dayStartHour = s.dayStartHour; m.safetyPage = s.safetyPage
                if let v = s.listenOffersRaw { m.listenOffersRaw = v }
                if let v = s.listenSpeak { m.listenSpeak = v }
                if let v = s.listenLongNote { m.listenLongNote = v }
                if let v = s.listenOfferPerson { m.listenOfferPerson = v }
                if let v = s.steadyFast { m.steadyFast = v }
                if let v = s.steadyHeavy { m.steadyHeavy = v }
                if let v = s.steadyLoop { m.steadyLoop = v }
                if let v = s.steadyFlooded { m.steadyFlooded = v }
                if let v = s.steadySigns { m.steadySigns = v }
                if let v = s.quietCheckOn { m.quietCheckOn = v }
                if let v = s.planSigns { m.planSigns = v }
                if let v = s.planCoping { m.planCoping = v }
                if let v = s.planPlaces { m.planPlaces = v }
                if let v = s.planHelpers { m.planHelpers = v }
                if let v = s.planPros { m.planPros = v }
                if let v = s.planSafeSpace { m.planSafeSpace = v }
                if let v = s.warningSigns { m.warningSigns = v }
                if let v = s.watchSigns { m.watchSigns = v }
                if let v = s.signsNoticedDay { m.signsNoticedDay = v }
                if let v = s.releaseAsks { m.releaseAsks = v }
                if let v = s.modelChoice { m.modelChoice = v }
                context.insert(m)
                add("AppSettings")
                summary.skipped += settings.count - 1
            } else {
                summary.skipped += settings.count
            }

            func merge<D, M: PersistentModel>(_ name: String, _ dtos: [D], _ type: M.Type, _ key: KeyPath<M, UUID>,
                                              id: (D) -> UUID, skip: (D) -> Bool = { _ in false }, build: (D) -> M) throws {
                var have = try ids(type, key)
                for d in dtos {
                    if have.contains(id(d)) || skip(d) { summary.skipped += 1; continue }
                    have.insert(id(d))
                    context.insert(build(d))
                    add(name)
                }
            }

            try merge("QuietTopic", topics, QuietTopic.self, \.syncId, id: { $0.syncId }) { d in
                let m = QuietTopic(term: d.term); m.syncId = d.syncId; m.updatedAt = d.updatedAt; return m
            }
            try merge("AboutMe", aboutMe, AboutMe.self, \.syncId, id: { $0.syncId }) { d in
                let m = AboutMe(markdown: d.markdown); m.syncId = d.syncId; m.updatedAt = d.updatedAt; return m
            }
            try merge("LifeEvent", events, LifeEvent.self, \.syncId, id: { $0.syncId }) { d in
                let m = LifeEvent(date: d.date, kind: .other, label: d.label)
                m.syncId = d.syncId; m.updatedAt = d.updatedAt; m.kindRaw = d.kindRaw; return m
            }

            // One summary per day and one check per week (enforced in code, not by constraint).
            let haveDays = Set(try context.fetch(FetchDescriptor<DaySummary>()).map(\.dayKey))
            try merge("DaySummary", days, DaySummary.self, \.syncId, id: { $0.syncId }, skip: { haveDays.contains($0.dayKey) }) { d in
                let m = DaySummary(day: AnchoredDay(key: d.dayKey) ?? AnchoredDay(year: 1970, month: 1, day: 1),
                                   timeZone: TimeZone(identifier: d.tz) ?? .current)
                m.syncId = d.syncId; m.updatedAt = d.updatedAt; m.deviceId = d.deviceId; m.dayKey = d.dayKey; m.tz = d.tz
                m.sleepMin = d.sleepMin; m.sleepDeepMin = d.sleepDeepMin; m.sleepRemMin = d.sleepRemMin
                m.sleepCoreMin = d.sleepCoreMin; m.awakeMin = d.awakeMin; m.sleepSourceRaw = d.sleepSourceRaw
                m.bedtime = d.bedtime; m.wakeTime = d.wakeTime; m.rested = d.rested
                m.restingHR = d.restingHR; m.manualHR = d.manualHR; m.weightKg = d.weightKg
                m.systolic = d.systolic; m.diastolic = d.diastolic; m.warningSigns = d.warningSigns
                m.hrvSDNN = d.hrvSDNN; m.respRate = d.respRate; m.wristTempC = d.wristTempC; m.steps = d.steps
                m.activeKcal = d.activeKcal; m.basalKcal = d.basalKcal; m.exerciseMin = d.exerciseMin
                m.menstrualFlow = d.menstrualFlow; m.cycleDay = d.cycleDay; m.phaseRaw = d.phaseRaw
                return m
            }

            try merge("Workout", workouts, Workout.self, \.syncId, id: { $0.syncId }) { d in
                let m = Workout(kind: .other, start: d.start, durationSec: d.durationSec)
                m.syncId = d.syncId; m.updatedAt = d.updatedAt; m.deviceId = d.deviceId
                m.healthId = d.healthId; m.hevyId = d.hevyId; m.kindRaw = d.kindRaw; m.title = d.title
                m.activeKcal = d.activeKcal; m.avgHR = d.avgHR; m.rpe = d.rpe; m.focusRaw = d.focusRaw; m.note = d.note
                m.ratedAt = d.ratedAt; m.promptedAt = d.promptedAt; m.aiEligible = d.aiEligible
                return m
            }
            try merge("HevySet", sets, HevySet.self, \.syncId, id: { $0.syncId }) { d in
                let m = HevySet(hevyWorkoutId: d.hevyWorkoutId, exerciseIndex: d.exerciseIndex, exerciseName: d.exerciseName, setIndex: d.setIndex)
                m.syncId = d.syncId; m.setType = d.setType; m.weightKg = d.weightKg; m.reps = d.reps
                m.rpe = d.rpe; m.distanceM = d.distanceM; m.durationSec = d.durationSec
                return m
            }

            let haveWeeks = Set(try context.fetch(FetchDescriptor<BodyCheck>()).map(\.weekKey))
            try merge("BodyCheck", checks, BodyCheck.self, \.syncId, id: { $0.syncId }, skip: { haveWeeks.contains($0.weekKey) }) { d in
                let m = BodyCheck(week: AnchoredDay(key: d.weekKey) ?? AnchoredDay(year: 1970, month: 1, day: 1))
                m.syncId = d.syncId; m.updatedAt = d.updatedAt; m.deviceId = d.deviceId; m.weekKey = d.weekKey
                m.signs = d.signs; m.tookAsUsualRaw = d.tookAsUsualRaw
                return m
            }
            try merge("LabResult", labs, LabResult.self, \.syncId, id: { $0.syncId }) { d in
                let m = LabResult(date: d.date, marker: d.marker)
                m.syncId = d.syncId; m.updatedAt = d.updatedAt; m.deviceId = d.deviceId
                m.value = d.value; m.unit = d.unit; m.low = d.low; m.high = d.high; m.note = d.note
                m.sourceRaw = d.sourceRaw; m.labRegionRaw = d.labRegionRaw; m.reportId = d.reportId
                return m
            }
            try merge("DoseChange", doses, DoseChange.self, \.syncId, id: { $0.syncId }) { d in
                let m = DoseChange(date: d.date, from: d.fromText, to: d.toText)
                m.syncId = d.syncId; m.updatedAt = d.updatedAt; m.deviceId = d.deviceId
                return m
            }
            try merge("MedicationLog", meds, MedicationLog.self, \.syncId, id: { $0.syncId }) { d in
                let m = MedicationLog(takenAt: d.takenAt)
                m.syncId = d.syncId; m.updatedAt = d.updatedAt; m.deviceId = d.deviceId
                m.medicationRef = d.medicationRef; m.sourceRaw = d.sourceRaw; m.with = d.with
                return m
            }
            try merge("GuessFeedback", guesses, GuessFeedback.self, \.syncId, id: { $0.syncId }) { d in
                let m = GuessFeedback(kind: d.kind, day: AnchoredDay(key: d.dayKey) ?? AnchoredDay(year: 1970, month: 1, day: 1))
                m.syncId = d.syncId; m.updatedAt = d.updatedAt; m.deviceId = d.deviceId; m.dayKey = d.dayKey
                m.guess = d.guess; m.fit = d.fit; m.shown = d.shown; m.picked = d.picked
                return m
            }
            try merge("AppFeedback", notes, AppFeedback.self, \.syncId, id: { $0.syncId }) { d in
                let m = AppFeedback(text: d.text, mood: d.mood)
                m.syncId = d.syncId; m.createdAt = d.createdAt
                return m
            }
            try merge("ExportRecord", exports, ExportRecord.self, \.syncId, id: { $0.syncId }) { d in
                let m = ExportRecord(kind: d.kind, rangeText: d.rangeText, deviceId: d.deviceId, date: d.date)
                m.syncId = d.syncId
                return m
            }
            try merge("ListenSession", listens, ListenSession.self, \.syncId, id: { $0.syncId }) { d in
                let m = ListenSession(date: d.date, seconds: d.seconds, offerRaw: d.offerRaw, helpedRaw: d.helpedRaw, deviceId: d.deviceId)
                m.syncId = d.syncId
                return m
            }
            try merge("DeletedEntry", deleted, DeletedEntry.self, \.syncId, id: { $0.syncId }) { d in
                let m = DeletedEntry(entryId: d.entryId, deletedAt: d.deletedAt, createdAt: d.createdAt, payload: d.payload, preview: d.preview)
                m.syncId = d.syncId
                m.photoData = files[mediaPath(d.syncId, "deleted-photo")]
                m.thumbData = files[mediaPath(d.syncId, "deleted-thumb")]
                m.audioData = files[mediaPath(d.syncId, "deleted-audio")]
                return m
            }
            try merge("TalkMemory", talks, TalkMemory.self, \.syncId, id: { $0.syncId }) { d in
                let m = TalkMemory(date: d.date, text: d.text, deviceId: d.deviceId)
                m.syncId = d.syncId
                m.updatedAt = d.updatedAt
                return m
            }
            try merge("TechniqueTry", tries, TechniqueTry.self, \.syncId, id: { $0.syncId }) { d in
                let m = TechniqueTry(date: d.date, techniqueId: d.techniqueId, state: HardState(rawValue: d.stateRaw) ?? .heavy,
                                     before: d.before, after: d.after, deviceId: d.deviceId)
                m.syncId = d.syncId
                return m
            }

            // Media: by syncId, and also skipped when the same play (dedupeKey) is already here,
            // so importing a file twice or restoring over a re-import never doubles a row.
            var haveKeys = Set(try context.fetch(FetchDescriptor<MediaItem>()).map(\.dedupeKey))
            try merge("MediaItem", media, MediaItem.self, \.syncId, id: { $0.syncId },
                      skip: { !$0.dedupeKey.isEmpty && haveKeys.contains($0.dedupeKey) }) { d in
                haveKeys.insert(d.dedupeKey)
                let m = MediaItem(source: .spotify, title: d.title, creator: d.creator, startedAt: d.startedAt, durationSec: d.durationSec)
                m.syncId = d.syncId; m.sourceRaw = d.sourceRaw; m.aiEligible = d.aiEligible
                m.dedupeKey = d.dedupeKey; m.deviceId = d.deviceId
                m.artistIds = d.artistIds; m.genres = d.genres
                return m
            }

            try merge("AppOpen", appOpens, AppOpen.self, \.syncId, id: { $0.syncId }, skip: { _ in false }) { d in
                let o = AppOpen(appName: d.appName, date: d.date, deviceId: d.deviceId)
                o.syncId = d.syncId
                return o
            }

            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return summary
    }
}
