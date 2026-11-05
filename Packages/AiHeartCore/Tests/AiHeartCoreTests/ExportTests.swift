import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import AiHeartCore

// Synthetic data only.

func exportContainer() throws -> ModelContainer { try AiHeartStore.makeContainer(inMemory: true) }

let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// One of every model, every optional set, so a lost field shows up.
@discardableResult
func seedEverything(_ c: ModelContext, deviceId: String = "dev-1") -> [UUID] {
    let day = AnchoredDay(year: 2026, month: 10, day: 5)

    let kept = Entry(kind: .photo, createdAt: t0, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    kept.deviceId = deviceId; kept.stateVersion = 3; kept.valence = 0.4; kept.arousal = -0.2; kept.word = "[synthetic] Calm"; kept.toneValence = 0.3; kept.toneArousal = -0.1
    kept.bodyRegions = ["chest", "jaw"]; kept.sensations = ["Tight"]; kept.text = "[synthetic] line one\nline two"
    kept.photoData = Data([1, 2, 3, 4]); kept.thumbData = Data([5, 6]); kept.audioData = Data([7, 8, 9]); kept.audioSeconds = 12.5
    kept.decidedBy = .auto; kept.embeddingId = UUID(); kept.keepNumbers = false
    c.insert(kept)

    let resting = Entry(kind: .write, createdAt: t0.addingTimeInterval(3600))
    resting.deviceId = deviceId; resting.text = "[synthetic] resting secret"; resting.word = "RestingWord"
    resting.releasedAt = t0.addingTimeInterval(1)   // odd for a resting entry, but it makes the field round-trip
    resting.status = .resting; resting.restUntil = t0.addingTimeInterval(86400 * 7); resting.keptLines = ["[synthetic] kept line"]
    var note = ReleaseNote(); note.feelings = [.tired]; note.thought = "[synthetic] a thought"; resting.releaseNote = note
    c.insert(resting)

    let released = Entry(kind: .write, createdAt: t0.addingTimeInterval(7200))
    released.deviceId = deviceId; released.text = "[synthetic] released secret"; released.word = "ReleasedWord"
    c.insert(released)
    _ = try? EntryLifecycle.purge(released, in: c, now: t0.addingTimeInterval(9000))
    released.keptLines = ["[synthetic] released kept line"]

    let s = AppSettings()
    s.pace = .monthly; s.resurfacing = true; s.pauseEverything = true; s.restDays = 9; s.decideAuto = false; s.keepNumbers = false
    s.outlookOn = false; s.usesCycle = false; s.usesLabs = false; s.usesTraining = false; s.faceIDLock = true
    s.askToRateWorkouts = false; s.rateWaitMinutes = 11; s.rateMinMinutes = 22; s.rateSkipIfHevyEffort = false
    s.reminderOn = true; s.reminderHour = 7; s.reminderMinute = 30; s.reminderDays = [2, 4]; s.reminderSkipIfWritten = false
    s.askForAppFeedback = false; s.dayStartHour = 5; s.safetyPage = "[synthetic] safety"
    s.listenOffers = .often; s.listenSpeak = true; s.listenLongNote = true; s.listenOfferPerson = true
    c.insert(s)

    c.insert(QuietTopic(term: "[synthetic] quiet"))
    c.insert(AboutMe(markdown: "[synthetic] about me"))
    c.insert(LifeEvent(date: t0, kind: .travel, label: "[synthetic] trip"))

    let d = DaySummary(day: day, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    d.deviceId = deviceId
    d.sleepMin = 420; d.sleepDeepMin = 60; d.sleepRemMin = 90; d.sleepCoreMin = 270; d.awakeMin = 15; d.sleepSourceRaw = "asleep"
    d.bedtime = t0; d.wakeTime = t0.addingTimeInterval(25200); d.rested = 4; d.restingHR = 58; d.manualHR = 61; d.weightKg = 55.5
    d.systolic = 110; d.diastolic = 70; d.warningSigns = ["chestPain"]; d.hrvSDNN = 48; d.respRate = 14.5; d.wristTempC = 35.9
    d.steps = 8123; d.activeKcal = 350.5; d.basalKcal = 1400; d.exerciseMin = 31; d.menstrualFlow = 2; d.cycleDay = 6; d.phaseRaw = "follicular"
    c.insert(d)

    let w = Workout(kind: .strength, start: t0, durationSec: 3600)
    w.deviceId = deviceId; w.healthId = "H-1"; w.hevyId = "hevy-1"; w.title = "[synthetic] Legs"; w.activeKcal = 300; w.avgHR = 120
    w.rpe = 8; w.focus = .legs; w.note = "[synthetic] note"; w.ratedAt = t0; w.promptedAt = t0; w.aiEligible = true
    c.insert(w)
    let strava = Workout(kind: .run, start: t0.addingTimeInterval(86400), durationSec: 1800)
    strava.deviceId = deviceId; strava.aiEligible = false
    c.insert(strava)

    let hs = HevySet(hevyWorkoutId: "hevy-1", exerciseIndex: 1, exerciseName: "[synthetic] Squat", setIndex: 2)
    hs.setType = "warmup"; hs.weightKg = 60; hs.reps = 5; hs.rpe = 7.5; hs.distanceM = 1; hs.durationSec = 40
    c.insert(hs)

    let tc = BodyCheck(week: day)
    tc.deviceId = deviceId; tc.signs = ["Tired": 2, "Cold": 1, "Shaky": 1]; tc.tookAsUsual = .mostly
    c.insert(tc)

    let report = UUID()
    let lab = LabResult(date: t0, marker: "GLU")
    lab.deviceId = deviceId; lab.value = 5.2; lab.unit = "mmol/L"; lab.low = 3.9; lab.high = 5.5; lab.note = "[synthetic] lab note"
    lab.sourceRaw = "screenshot"; lab.labRegionRaw = "jp"; lab.reportId = report
    c.insert(lab)
    let lab2 = LabResult(date: t0, marker: "LDL")
    lab2.deviceId = deviceId; lab2.value = 110; lab2.unit = "mg/dL"; lab2.sourceRaw = "screenshot"; lab2.reportId = report
    c.insert(lab2)

    let dose = DoseChange(date: t0, from: "50 mcg", to: "75 mcg")
    dose.deviceId = deviceId
    c.insert(dose)

    let med = MedicationLog(takenAt: t0)
    med.deviceId = deviceId; med.medicationRef = "daily"; med.sourceRaw = "manual"; med.with = ["coffee"]
    c.insert(med)

    let g = GuessFeedback(kind: "lean", day: day)
    g.deviceId = deviceId; g.guess = "usual"; g.fit = true; g.shown = ["Wired", "Calm"]; g.picked = "Calm"
    c.insert(g)

    c.insert(AppFeedback(text: "[synthetic] app note", mood: "ok"))
    c.insert(ExportRecord(kind: "backup", rangeText: "All time", deviceId: deviceId, date: t0))

    c.insert(ListenSession(date: t0, seconds: 321, offerRaw: "reflect", helpedRaw: "aBit", deviceId: deviceId))
    c.insert(TechniqueTry(date: t0, techniqueId: "sigh", state: .fast, before: 7, after: 4, deviceId: deviceId))
    c.insert(TalkMemory(date: t0, text: "[synthetic] what I said in a talk", deviceId: deviceId))
    c.insert(DeletedEntry(entryId: UUID(), deletedAt: t0, createdAt: t0, payload: Data("{}".utf8), preview: "[synthetic] deleted"))

    let media = MediaItem(source: .netflix, title: "[synthetic] Show: Episode 1", creator: "[synthetic] Channel", startedAt: t0, durationSec: 2530)
    media.deviceId = deviceId
    media.artistIds = "[synthetic]id1"; media.genres = "[synthetic] indie pop"
    c.insert(media)
    c.insert(AppOpen(appName: "[synthetic] App", date: t0, deviceId: deviceId))

    try! c.save()
    return [kept.syncId, resting.syncId, released.syncId]
}

@Suite struct ZipTests {
    @Test func roundTripWithChecksums() throws {
        var z = ZipWriter()
        let big = Data((0..<5000).map { UInt8($0 % 251) })
        z.add("a.txt", Data("hello".utf8))
        z.add("dir/ünï.json", big)
        z.add("empty", Data())
        let out = try ZipReader.entries(z.finish())
        #expect(out["a.txt"] == Data("hello".utf8))
        #expect(out["dir/ünï.json"] == big)
        #expect(out["empty"] == Data())
        #expect(out.count == 3)
    }

    @Test func crcKnownValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func corruptionIsCaught() throws {
        var z = ZipWriter()
        z.add("a.txt", Data("hello world".utf8))
        var bytes = z.finish()
        let i = bytes.range(of: Data("hello".utf8))!.lowerBound
        bytes[i] ^= 0xFF
        #expect(throws: ZipError.self) { try ZipReader.entries(bytes) }
        #expect(throws: ZipError.self) { try ZipReader.entries(Data("nope".utf8)) }
    }

    @Test func systemUnzipAcceptsIt() throws {
        #if os(macOS)
        var z = ZipWriter()
        z.add("a.txt", Data("hello".utf8))
        z.add("b/c.txt", Data("world".utf8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ziptest-\(UUID().uuidString).zip")
        try z.finish().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-tq", url.path]
        p.standardOutput = Pipe()
        try p.run(); p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        #endif
    }
}

@Suite struct XLSXTests {
    func files(_ sheets: [Sheet]) throws -> [String: String] {
        try ZipReader.entries(XLSXWriter.make(sheets, timeZone: TimeZone(identifier: "UTC")!)).mapValues { String(decoding: $0, as: UTF8.self) }
    }

    @Test func partsAndEscaping() throws {
        let f = try files([Sheet(name: "Days", header: ["Date <x>", "Amount (kg)"],
                                 rows: [[.text("a <b> & \"c\"\nline2"), .number(1.5)], [.date(Date(timeIntervalSince1970: 0)), .number(3)], [.empty, .empty]])])
        for part in ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/worksheets/sheet1.xml"] {
            #expect(f[part] != nil, "missing \(part)")
        }
        let sheet = f["xl/worksheets/sheet1.xml"]!
        #expect(sheet.contains("a &lt;b&gt; &amp; &quot;c&quot;\nline2"))
        #expect(sheet.contains("Date &lt;x&gt;"))
        #expect(sheet.contains("t=\"inlineStr\""))
        #expect(sheet.contains("state=\"frozen\""))
        #expect(sheet.contains("<c r=\"B2\" s=\"3\"><v>1.5</v></c>"))
        #expect(sheet.contains("<c r=\"B3\"><v>3.0</v></c>"))
        // 1970-01-01 00:00 UTC is serial 25569.
        #expect(sheet.contains("<c r=\"A3\" s=\"2\"><v>25569.00000000</v></c>"))
        #expect(f["xl/styles.xml"]!.contains("yyyy\\-mm\\-dd\\ hh:mm"))
        #expect(f["xl/workbook.xml"]!.contains("<sheet name=\"Days\""))
    }

    @Test func sheetNamesAreSafe() {
        #expect(XLSXWriter.sanitizedName("a[b]:c*d?e/f\\g") == "abcdefg")
        #expect(XLSXWriter.sanitizedName(String(repeating: "x", count: 50)).count == 31)
        #expect(XLSXWriter.sanitizedName("") == "Sheet")
        #expect(XLSXWriter.sanitizedName("'quoted'") == "quoted")
    }

    @Test func duplicateNamesAndControlCharacters() throws {
        let f = try files([Sheet(name: "A", header: ["h"], rows: [[.text("x\u{01}y")]]), Sheet(name: "a", header: [], rows: [])])
        let wb = f["xl/workbook.xml"]!
        #expect(wb.contains("name=\"A\"") && wb.contains("name=\"a 2\""))
        #expect(f["xl/worksheets/sheet1.xml"]!.contains(">xy<"))
        #expect(f["xl/worksheets/sheet2.xml"] != nil)
    }

    @Test func emptyWorkbookStillHasASheet() throws {
        let f = try files([])
        #expect(f["xl/worksheets/sheet1.xml"] != nil)
    }

    @Test func wellFormedXML() throws {
        let data = XLSXWriter.make([Sheet(name: "S", header: ["a"], rows: [[.text("<&>")]])])
        for (name, d) in try ZipReader.entries(data) {
            let p = XMLParser(data: d)
            #expect(p.parse(), "\(name) not well-formed")
        }
    }
}

@Suite struct CryptoTests {
    let fast = 1000

    @Test func roundTrip() throws {
        let plain = Data("[synthetic] secrets".utf8)
        let sealed = try BackupCrypto.seal(plain, passphrase: "correct horse", iterations: fast)
        #expect(sealed.prefix(8) == Data("AIHEART1".utf8))
        #expect(!sealed.contains(plain))
        #expect(try BackupCrypto.open(sealed, passphrase: "correct horse") == plain)
        // Fresh salt each time.
        #expect(try BackupCrypto.seal(plain, passphrase: "correct horse", iterations: fast) != sealed)
    }

    @Test func headerLayout() throws {
        let sealed = try BackupCrypto.seal(Data([1]), passphrase: "p", iterations: 600_000 / 600)
        #expect(sealed.count == 8 + 16 + 4 + 12 + 1 + 16)
        #expect(Array(sealed[24..<28]) == [0, 0, 0x03, 0xE8])
    }

    @Test func wrongPassphrase() throws {
        let sealed = try BackupCrypto.seal(Data("x".utf8), passphrase: "right", iterations: fast)
        #expect(throws: BackupError.wrongPassphrase) { try BackupCrypto.open(sealed, passphrase: "wrong") }
    }

    @Test func tamperedBytesFail() throws {
        let sealed = try BackupCrypto.seal(Data("hello there".utf8), passphrase: "pw", iterations: fast)
        for index in [10, 26, 30, sealed.count - 20, sealed.count - 1] {
            var bad = sealed
            bad[index] ^= 0x01
            #expect(throws: BackupError.self) { try BackupCrypto.open(bad, passphrase: "pw") }
        }
    }

    @Test func notABackup() {
        #expect(throws: BackupError.notABackup) { try BackupCrypto.open(Data("hello".utf8), passphrase: "pw") }
        #expect(throws: BackupError.notABackup) { try BackupCrypto.open(Data(repeating: 0, count: 100), passphrase: "pw") }
    }

    @Test func unicodePassphraseNormalised() throws {
        let sealed = try BackupCrypto.seal(Data("x".utf8), passphrase: "caf\u{E9}", iterations: fast)
        #expect(try BackupCrypto.open(sealed, passphrase: "cafe\u{301}") == Data("x".utf8))
    }

    @Test func emptyPassphraseRefused() {
        #expect(throws: BackupError.emptyPassphrase) { try BackupCrypto.seal(Data(), passphrase: "", iterations: fast) }
    }
}

@Suite struct BackupArchiveTests {
    func json(_ files: [String: Data], _ name: String) throws -> [[String: Any]] {
        try JSONSerialization.jsonObject(with: files[name] ?? Data("[]".utf8)) as! [[String: Any]]
    }

    @Test func dtosCoverEveryPersistedAttribute() throws {
        let c = ModelContext(try exportContainer())
        seedEverything(c)
        let files = try ZipReader.entries(BackupArchive.make(context: c))
        let fileFor: [String: String] = [
            "Entry": "entries.json", "PurgeRecord": "purgeRecords.json", "AppSettings": "appSettings.json", "QuietTopic": "quietTopics.json",
            "AboutMe": "aboutMe.json", "LifeEvent": "lifeEvents.json", "DaySummary": "daySummaries.json", "Workout": "workouts.json",
            "HevySet": "hevySets.json", "BodyCheck": "bodyChecks.json", "LabResult": "labResults.json", "DoseChange": "doseChanges.json",
            "MedicationLog": "medicationLogs.json", "GuessFeedback": "guessFeedback.json", "AppFeedback": "appFeedback.json",
            "ExportRecord": "exportRecords.json", "ListenSession": "listenSessions.json", "MediaItem": "mediaItems.json",
            "AppOpen": "appOpens.json", "TechniqueTry": "techniqueTries.json", "TalkMemory": "talkMemories.json", "DeletedEntry": "deletedEntries.json",
        ]
        let media: Set<String> = ["photoData", "thumbData", "audioData"]
        let schema = Schema(AiHeartSchema.models)
        #expect(schema.entities.count == fileFor.count)
        for entity in schema.entities {
            let file = try #require(fileFor[entity.name], "no backup file for \(entity.name)")
            let rows = try json(files, file)
            #expect(!rows.isEmpty, "\(file) empty")
            let keys = Set(rows.flatMap { $0.keys })   // nil optionals are omitted, so look across rows
            for attr in entity.attributes where !media.contains(attr.name) {
                #expect(keys.contains(attr.name), "\(entity.name).\(attr.name) missing from backup")
            }
        }
        let entry = try #require(try json(files, "entries.json").first { ($0["word"] as? String) == "[synthetic] Calm" })
        let id = try #require(entry["syncId"] as? String)
        #expect(files["media/\(id)-photo.jpg"] == Data([1, 2, 3, 4]))
        #expect(files["media/\(id)-thumb.jpg"] == Data([5, 6]))
        #expect(files["media/\(id)-audio.m4a"] == Data([7, 8, 9]))
    }

    @Test func manifest() throws {
        let c = ModelContext(try exportContainer())
        seedEverything(c)
        let files = try ZipReader.entries(BackupArchive.make(context: c))
        let m = try #require(JSONSerialization.jsonObject(with: files["manifest.json"]!) as? [String: Any])
        #expect(m["format"] as? Int == BackupArchive.formatVersion)
        #expect(m["created"] != nil)
        let counts = try #require(m["counts"] as? [String: Int])
        #expect(counts["Entry"] == 2)          // kept + resting; released not included
        #expect(counts["PurgeRecord"] == 1)
        #expect(counts["Workout"] == 2)
    }

    @Test func roundTripReproducesEveryModel() throws {
        let a = ModelContext(try exportContainer())
        seedEverything(a)
        let archive = try BackupArchive.make(context: a)

        let b = ModelContext(try exportContainer())
        let summary = try BackupArchive.restore(archive, into: b)
        #expect(summary.added["Entry"] == 2)
        #expect(summary.added["PurgeRecord"] == 1)
        #expect(summary.added["AppSettings"] == 1)
        #expect(summary.skipped == 0)
        #expect(summary.added.count == 22)

        // Re-export from the restored store: same bytes in every file but the manifest date.
        let one = try ZipReader.entries(archive), two = try ZipReader.entries(BackupArchive.make(context: b))
        #expect(Set(one.keys) == Set(two.keys))
        for (name, data) in one where name != "manifest.json" { #expect(two[name] == data, "\(name) differs after restore") }

        // And spot-check live values, media included.
        let e = try #require(try b.fetch(FetchDescriptor<Entry>()).first { $0.word == "[synthetic] Calm" })
        #expect(e.photoData == Data([1, 2, 3, 4]) && e.thumbData == Data([5, 6]) && e.audioData == Data([7, 8, 9]))
        #expect(e.tz == "Asia/Tokyo" && e.createdAt == t0 && e.stateVersion == 3 && !e.keepNumbers && e.decidedBy == .auto)
        let resting = try #require(try b.fetch(FetchDescriptor<Entry>()).first { $0.status == .resting })
        #expect(resting.keptLines == ["[synthetic] kept line"] && resting.restUntil != nil)
        let s = try #require(try b.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(s.pace == .monthly && s.reminderDays == [2, 4] && s.safetyPage == "[synthetic] safety")
        #expect(s.listenOffers == .often && s.listenSpeak && s.listenLongNote && s.listenOfferPerson)
        let ls = try #require(try b.fetch(FetchDescriptor<ListenSession>()).first)
        #expect(ls.date == t0 && ls.seconds == 321 && ls.offerRaw == "reflect" && ls.helpedRaw == "aBit" && ls.deviceId == "dev-1")
        let mi = try #require(try b.fetch(FetchDescriptor<MediaItem>()).first)
        #expect(mi.source == .netflix && mi.title == "[synthetic] Show: Episode 1" && mi.creator == "[synthetic] Channel")
        #expect(mi.startedAt == t0 && mi.durationSec == 2530 && !mi.aiEligible && mi.deviceId == "dev-1")
        #expect(mi.dedupeKey.hasPrefix("netflix|[synthetic] show: episode 1|"))
        let d = try #require(try b.fetch(FetchDescriptor<DaySummary>()).first)
        #expect(d.dayKey == "2026-10-05" && d.restingHR == 58 && d.warningSigns == ["chestPain"] && d.phaseRaw == "follicular")
        let tc = try #require(try b.fetch(FetchDescriptor<BodyCheck>()).first)
        #expect(tc.signs == ["Tired": 2, "Cold": 1, "Shaky": 1] && tc.tookAsUsual == .mostly)
        let labs = try b.fetch(FetchDescriptor<LabResult>()).sorted { $0.marker < $1.marker }
        #expect(labs.map(\.marker) == ["GLU", "LDL"])
        #expect(labs[0].value == 5.2 && labs[0].unit == "mmol/L" && labs[0].low == 3.9 && labs[0].high == 5.5)
        #expect(labs[0].reportId != nil && labs[0].reportId == labs[1].reportId)
        #expect(try b.fetchCount(FetchDescriptor<HevySet>()) == 1)
    }

    @Test func restoreTwiceAddsNothing() throws {
        let a = ModelContext(try exportContainer())
        seedEverything(a)
        let archive = try BackupArchive.make(context: a)
        let b = ModelContext(try exportContainer())
        _ = try BackupArchive.restore(archive, into: b)
        let again = try BackupArchive.restore(archive, into: b)
        #expect(again.added.isEmpty)
        #expect(again.skipped > 0)
        #expect(try b.fetchCount(FetchDescriptor<Entry>()) == 2)   // kept and resting; the released copy never came
        // Restoring onto the source itself also adds nothing.
        #expect(try BackupArchive.restore(archive, into: a).added.isEmpty)
    }

    @Test func tombstonedEntryIsNotRestored() throws {
        let a = ModelContext(try exportContainer())
        let ids = seedEverything(a)
        let archive = try BackupArchive.make(context: a)

        // Fresh device that already knows the first entry was purged.
        let b = ModelContext(try exportContainer())
        b.insert(PurgeRecord(entryId: ids[0], purgedAt: t0))
        try b.save()
        let summary = try BackupArchive.restore(archive, into: b)
        #expect(summary.added["Entry"] == 1)
        let restored = try b.fetch(FetchDescriptor<Entry>())
        #expect(!restored.contains { $0.syncId == ids[0] })
        #expect(restored.contains { $0.syncId == ids[1] })
    }

    @Test func releasedEntriesAbsentFromBackup() throws {
        let c = ModelContext(try exportContainer())
        let ids = seedEverything(c)
        let data = try BackupArchive.make(context: c)
        let files = try ZipReader.entries(data)
        let all = files.values.map { String(decoding: $0, as: UTF8.self) }.joined()
        #expect(!all.contains("released secret") && !all.contains("ReleasedWord") && !all.contains("released kept line"))
        let entries = try JSONSerialization.jsonObject(with: files["entries.json"]!) as! [[String: Any]]
        #expect(!entries.contains { ($0["syncId"] as? String) == ids[2].uuidString })
        let purges = try JSONSerialization.jsonObject(with: files["purgeRecords.json"]!) as! [[String: Any]]
        #expect(purges.contains { ($0["entryId"] as? String) == ids[2].uuidString })
    }

    @Test func demoRowsExcluded() throws {
        let c = ModelContext(try exportContainer())
        seedEverything(c, deviceId: "demo")
        let files = try ZipReader.entries(BackupArchive.make(context: c))
        for name in ["entries", "daySummaries", "workouts", "hevySets", "bodyChecks", "labResults", "doseChanges",
                     "medicationLogs", "guessFeedback", "exportRecords", "listenSessions", "mediaItems"] {
            #expect(try json(files, "\(name).json").isEmpty, "\(name) kept demo rows")
        }
        #expect(!files.keys.contains { $0.hasPrefix("media/") })
        // Rows with no device id (settings, topics) are not demo data.
        #expect(try json(files, "appSettings.json").count == 1)
    }

    @Test func settingsOnlyIfNoneExists() throws {
        let a = ModelContext(try exportContainer())
        seedEverything(a)
        let archive = try BackupArchive.make(context: a)
        let b = ModelContext(try exportContainer())
        let mine = AppSettings(); mine.restDays = 3
        b.insert(mine); try b.save()
        let summary = try BackupArchive.restore(archive, into: b)
        #expect(summary.added["AppSettings"] == nil)
        let all = try b.fetch(FetchDescriptor<AppSettings>())
        #expect(all.count == 1 && all[0].restDays == 3)
    }

    @Test func badInputsThrowAndRestoreNothing() throws {
        let b = ModelContext(try exportContainer())
        #expect(throws: BackupError.notABackup) { try BackupArchive.restore(Data("junk".utf8), into: b) }
        var z = ZipWriter()
        z.add("manifest.json", Data(#"{"format":99,"created":0,"counts":{}}"#.utf8))
        #expect(throws: BackupError.unsupportedVersion(99)) { try BackupArchive.restore(z.finish(), into: b) }
        // A damaged table fails before anything is inserted.
        var y = ZipWriter()
        y.add("manifest.json", Data(#"{"format":1,"created":0,"counts":{}}"#.utf8))
        y.add("quietTopics.json", Data(#"[{"syncId":"x"}]"#.utf8))
        #expect(throws: BackupError.notABackup) { try BackupArchive.restore(y.finish(), into: b) }
        #expect(try b.fetchCount(FetchDescriptor<QuietTopic>()) == 0)
    }

    @Test func sealedBackupEndToEnd() throws {
        let a = ModelContext(try exportContainer())
        seedEverything(a)
        let sealed = try BackupCrypto.seal(BackupArchive.make(context: a), passphrase: "pw", iterations: 1000)
        let b = ModelContext(try exportContainer())
        let summary = try BackupArchive.restore(BackupCrypto.open(sealed, passphrase: "pw"), into: b)
        #expect(summary.added["Entry"] == 2)
    }
}

@Suite struct SpreadsheetExportTests {
    func sheets(_ c: ModelContext, _ o: ExportOptions = ExportOptions()) throws -> [String: Sheet] {
        Dictionary(uniqueKeysWithValues: try SpreadsheetExport.sheets(context: c, options: o).map { ($0.name, $0) })
    }

    func texts(_ s: Sheet) -> [String] {
        s.rows.flatMap { $0 }.compactMap { if case .text(let t) = $0 { t } else { nil } }
    }

    @Test func sheetsAndHeaders() throws {
        let c = ModelContext(try exportContainer())
        seedEverything(c)
        let s = try SpreadsheetExport.sheets(context: c, options: ExportOptions())
        #expect(s.map(\.name) == ["Days", "Entries", "Workouts", "Hevy sets", "Labs", "Dose changes", "Dose log", "Weekly checks", "Media"])
        let days = try #require(s.first)
        #expect(days.rows.count == 1)
        #expect(days.header.contains("Sleep (h)") && days.header.contains("Wrist temp (°C)"))
        #expect(days.rows[0][1] == .number(7))       // 420 min
        for sheet in s { for r in sheet.rows { #expect(r.count == sheet.header.count, "\(sheet.name) row width") } }
        // It really is a workbook.
        let files = try ZipReader.entries(XLSXWriter.make(s))
        #expect(files["xl/worksheets/sheet9.xml"] != nil)
    }

    @Test func releasedNeverAndRestingOnlyKeptLines() throws {
        let c = ModelContext(try exportContainer())
        seedEverything(c)
        let s = try sheets(c, ExportOptions(includeJournalText: true))
        let entries = try #require(s["Entries"])
        #expect(entries.rows.count == 2)
        let all = s.values.flatMap { texts($0) }.joined(separator: "|")
        #expect(!all.contains("released") && !all.contains("Released"))
        #expect(!all.contains("RestingWord") && !all.contains("resting secret"))
        #expect(all.contains("[synthetic] kept line"))
        #expect(all.contains("[synthetic] line one"))
    }

    @Test func journalTextOnlyWhenAsked() throws {
        let c = ModelContext(try exportContainer())
        seedEverything(c)
        let off = try #require(try sheets(c)["Entries"])
        #expect(!off.header.contains("Journal text") && !off.header.contains("Caption"))
        #expect(!texts(off).joined().contains("line one"))
        #expect(texts(off).contains("[synthetic] Calm"))   // word still exports
        let on = try #require(try sheets(c, ExportOptions(includeJournalText: true))["Entries"])
        #expect(on.header.contains("Journal text"))
    }

    @Test func includeBodyFalseDropsBodySheets() throws {
        let c = ModelContext(try exportContainer())
        seedEverything(c)
        let s = try sheets(c, ExportOptions(includeBody: false))
        #expect(s["Days"] == nil && s["Workouts"] == nil && s["Hevy sets"] == nil)
        #expect(s["Labs"] != nil && s["Entries"] != nil && s["Weekly checks"] != nil)
    }

    @Test func rangeIsRespected() throws {
        let c = ModelContext(try exportContainer())
        seedEverything(c)
        let after = try sheets(c, ExportOptions(from: t0.addingTimeInterval(86400 * 30)))
        for (name, sheet) in after where name != "Days" && name != "Weekly checks" { #expect(sheet.rows.isEmpty, "\(name)") }
        let before = try sheets(c, ExportOptions(to: t0.addingTimeInterval(-86400 * 30)))
        for (_, sheet) in before { #expect(sheet.rows.isEmpty) }
        let narrow = try sheets(c, ExportOptions(from: t0.addingTimeInterval(-10), to: t0.addingTimeInterval(1800)))
        #expect(narrow["Entries"]?.rows.count == 1 && narrow["Workouts"]?.rows.count == 1 && narrow["Hevy sets"]?.rows.count == 1)
    }

    @Test func stravaRowsAreMarked() throws {
        let c = ModelContext(try exportContainer())
        seedEverything(c)
        let w = try #require(try sheets(c)["Workouts"])
        #expect(w.rows.count == 2)
        #expect(texts(w).contains("Strava (display only)"))
        #expect(texts(w).contains("Apple Health + Hevy"))
    }

    @Test func neverIncludesPrivateTables() throws {
        let c = ModelContext(try exportContainer())
        seedEverything(c)
        let all = try SpreadsheetExport.sheets(context: c, options: ExportOptions(includeJournalText: true))
            .flatMap { texts($0) + $0.header }.joined(separator: "|")
        for secret in ["[synthetic] about me", "[synthetic] quiet", "[synthetic] app note", "[synthetic] safety", "[synthetic] lab note"] {
            #expect(!all.contains(secret), "\(secret) leaked")
        }
    }

    @Test func demoRowsExcluded() throws {
        let c = ModelContext(try exportContainer())
        seedEverything(c, deviceId: "demo")
        let s = try sheets(c, ExportOptions(includeJournalText: true))
        for name in ["Days", "Entries", "Workouts", "Hevy sets", "Labs", "Dose changes", "Dose log", "Weekly checks", "Media"] {
            #expect(s[name]?.rows.isEmpty == true, "\(name) has demo rows")
        }
    }
}
