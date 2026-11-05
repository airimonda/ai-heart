import Foundation
import SwiftData
import Testing
@testable import AiHeartCore

// Synthetic data only. Every title and name below is made up.

private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi, second: s))!
}

private let UTCZ = TimeZone(identifier: "UTC")!

@Suite struct NetflixImportTests {
    @Test func simpleCSVWithBOMCRLFQuotesAndMonthFirstDates() throws {
        // [synthetic]
        let csv = "\u{FEFF}Title,Date\r\n\"[synthetic] Show, The: Season 1: \"\"Pilot\"\"\",10/31/26\r\n[synthetic] Film,11/1/26\r\n"
        let rows = try MediaImport.netflix(Data(csv.utf8), timeZone: UTCZ)
        #expect(rows.count == 2)
        #expect(rows[0].title == "[synthetic] Show, The: Season 1: \"Pilot\"")
        #expect(rows[0].startedAt == utc(2026, 10, 31, 12))      // no time: noon
        #expect(rows[0].creator == nil && rows[0].durationSec == nil)
        #expect(rows[1].startedAt == utc(2026, 11, 1, 12))
    }

    @Test func dayFirstDatesAndFileWideHint() throws {
        // [synthetic] 31/10 is clearly day-first, so 01/11/2026 in the same file is 1 November, not 11 January.
        let csv = "Title,Date\n[synthetic] A,31/10/2026\n[synthetic] B,01/11/2026\n"
        let rows = try MediaImport.netflix(Data(csv.utf8), timeZone: UTCZ)
        #expect(rows.map(\.startedAt) == [utc(2026, 10, 31, 12), utc(2026, 11, 1, 12)])
    }

    @Test func ambiguousDatesDefaultToMonthFirstAndShortYearsAre20xx() throws {
        // [synthetic]
        let rows = try MediaImport.netflix(Data("Title,Date\n[synthetic] A,03/04/26\n".utf8), timeZone: UTCZ)
        #expect(rows[0].startedAt == utc(2026, 3, 4, 12))
    }

    @Test func impossibleDatesAreSkipped() throws {
        // [synthetic]
        let rows = try MediaImport.netflix(Data("Title,Date\n[synthetic] A,31/31/2026\n[synthetic] B,02/30/2026\n[synthetic] C,10/05/2026\n".utf8), timeZone: UTCZ)
        #expect(rows.map(\.title) == ["[synthetic] C"])
    }

    @Test func noonIsLocalToTheGivenTimeZone() throws {
        // [synthetic]
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let rows = try MediaImport.netflix(Data("Title,Date\n[synthetic] A,10/31/26\n".utf8), timeZone: tokyo)
        #expect(rows[0].startedAt == utc(2026, 10, 31, 3))       // 12:00 JST
    }

    static let full: String = [
        "Profile Name,Start Time,Duration,Attributes,Title,Supplemental Video Type,Device Type,Bookmark,Latest Bookmark,Country",
        "Alex,2026-10-31 21:15:03,00:42:10,,\"[synthetic] Show, The: Season 1: \"\"Ep 1\"\"\",,Smart TV,00:42:10,Not latest view,JP",
        "Alex,2026-10-31 22:00:00,00:01:10,Autoplayed: user action: None;,[synthetic] Show: Ep 2,,Smart TV,00:01:10,Not latest view,JP",
        "Alex,2026-10-31 22:05:00,00:30:00,Autoplayed: user action: None;,[synthetic] Show: Ep 3,,Smart TV,00:30:00,Not latest view,JP",
        "Alex,2026-11-01 08:00:00,00:00:30,,[synthetic] Trailer,TRAILER,Phone,00:00:30,Not latest view,JP",
        "Alex,2026-11-01 08:01:00,00:00:20,,[synthetic] Hook,HOOK,Phone,00:00:20,Not latest view,JP",
        "Sam,2026-11-01 09:00:00,01:35:00,,[synthetic] Film,,Phone,01:35:00,Latest view,JP",
        "Alex,2026-11-01 10:00:00,00:00:00,,[synthetic] Zero length,,Phone,00:00:00,Latest view,JP",
    ].joined(separator: "\r\n") + "\r\n"

    @Test func downloadAllExport() throws {
        let rows = try MediaImport.netflix(Data(("\u{FEFF}" + Self.full).utf8))
        #expect(rows.map(\.title) == [
            "[synthetic] Show, The: Season 1: \"Ep 1\"",    // quoted comma and escaped quotes
            "[synthetic] Show: Ep 3",                        // autoplayed but 30 min: kept
            "[synthetic] Film",
            "[synthetic] Zero length",
        ])
        #expect(rows[0].startedAt == utc(2026, 10, 31, 21, 15, 3))   // Start Time is UTC
        #expect(rows[0].durationSec == 2530)
        #expect(rows[3].durationSec == nil)                          // 0 means unknown, not zero minutes
    }

    @Test func profileFilter() throws {
        let sam = try MediaImport.netflix(Data(Self.full.utf8), profile: "sam")
        #expect(sam.map(\.title) == ["[synthetic] Film"])
        #expect(try MediaImport.netflix(Data(Self.full.utf8), profile: "Nobody").isEmpty)
    }

    @Test func unknownShapeThrows() {
        #expect(throws: MediaImportError.unrecognizedFormat) { try MediaImport.netflix(Data("a,b\n1,2\n".utf8)) }
        #expect(throws: MediaImportError.unrecognizedFormat) { try MediaImport.netflix(Data()) }
        #expect(throws: MediaImportError.unrecognizedFormat) { try MediaImport.netflix(Data("Title,Other\nx,y\n".utf8)) }
    }

    @Test func quotedNewlineStaysInOneField() throws {
        // [synthetic]
        let rows = try MediaImport.netflix(Data("Title,Date\n\"[synthetic] Line one\nline two\",10/31/26\n".utf8), timeZone: UTCZ)
        #expect(rows.count == 1 && rows[0].title == "[synthetic] Line one\nline two")
    }
}

@Suite struct YouTubeImportTests {
    // [synthetic]
    static let json = """
    [
      {"header":"YouTube","title":"Watched [synthetic] Video One","titleUrl":"https://www.youtube.com/watch?v=aaa",
       "subtitles":[{"name":"[synthetic] Channel A","url":"https://www.youtube.com/channel/x"}],
       "time":"2026-10-31T13:15:03.123Z","products":["YouTube"]},
      {"header":"YouTube","title":"Watched [synthetic] Ad","titleUrl":"https://www.youtube.com/watch?v=bbb",
       "subtitles":[{"name":"[synthetic] Advertiser"}],"details":[{"name":"From Google Ads"}],"time":"2026-10-31T13:20:00.000Z"},
      {"header":"YouTube","title":"Watched a video that has been removed","time":"2026-10-31T13:30:00.000Z"},
      {"header":"YouTube","title":"[synthetic] Video Two を視聴しました","titleUrl":"https://www.youtube.com/watch?v=ccc",
       "subtitles":[{"name":"[synthetic] チャンネル"}],"time":"2026-10-30T09:00:00Z"},
      {"header":"YouTube","title":"Pinanood ang [synthetic] Video Three","titleUrl":"https://www.youtube.com/watch?v=ddd",
       "time":"2026-10-29T09:00:00.500Z"},
      {"header":"YouTube","title":"Watched [synthetic] No Time","titleUrl":"https://www.youtube.com/watch?v=eee"}
    ]
    """

    @Test func parsesAndSkips() throws {
        let rows = try MediaImport.youtube(Data(Self.json.utf8))
        #expect(rows.map(\.title) == ["[synthetic] Video One", "[synthetic] Video Two", "[synthetic] Video Three"])
        #expect(rows[0].creator == "[synthetic] Channel A")
        #expect(abs(rows[0].startedAt.timeIntervalSince(utc(2026, 10, 31, 13, 15, 3)) - 0.123) < 0.001)
        #expect(rows[1].creator == "[synthetic] チャンネル")
        #expect(rows[1].startedAt == utc(2026, 10, 30, 9))       // no fractional seconds still parses
        #expect(rows[2].creator == nil)
        #expect(rows.allSatisfy { $0.durationSec == nil })
    }

    @Test func notJSONThrows() {
        #expect(throws: MediaImportError.unrecognizedFormat) { try MediaImport.youtube(Data("nope".utf8)) }
        #expect(throws: MediaImportError.unrecognizedFormat) { try MediaImport.youtube(Data("{}".utf8)) }
        #expect((try? MediaImport.youtube(Data("[]".utf8)))?.isEmpty == true)
    }
}

@Suite struct SpotifyImportTests {
    // [synthetic]
    static let json = """
    {"items":[
      {"track":{"name":"[synthetic] Song A","duration_ms":200000,"artists":[{"name":"[synthetic] One"},{"name":"[synthetic] Two"}]},
       "played_at":"2026-10-31T13:15:03.456Z"},
      {"track":{"name":"[synthetic] Song B","duration_ms":61500,"artists":[{"name":"[synthetic] Solo"}]},
       "played_at":"2026-10-31T13:11:40Z"},
      {"track":null,"played_at":"2026-10-31T13:00:00Z"},
      {"track":{"name":"[synthetic] No time","duration_ms":1000,"artists":[]}}
    ],"next":null}
    """

    @Test func startIsEndMinusLength() throws {
        let rows = try MediaImport.spotifyRecentlyPlayed(Data(Self.json.utf8))
        #expect(rows.count == 2)
        #expect(rows[0].title == "[synthetic] Song A" && rows[0].creator == "[synthetic] One, [synthetic] Two")
        #expect(rows[0].durationSec == 200)
        #expect(abs(rows[0].startedAt.timeIntervalSince(utc(2026, 10, 31, 13, 11, 43)) - 0.456) < 0.001)   // 13:15:03.456 - 200 s
        #expect(abs(rows[1].startedAt.timeIntervalSince(utc(2026, 10, 31, 13, 10, 38)) - 0.5) < 0.001)   // 13:11:40 - 61.5 s
        #expect(rows[1].durationSec == 61.5)
    }

    @Test func notTheRightJSONThrows() {
        #expect(throws: MediaImportError.unrecognizedFormat) { try MediaImport.spotifyRecentlyPlayed(Data("[]".utf8)) }
        #expect(throws: MediaImportError.unrecognizedFormat) { try MediaImport.spotifyRecentlyPlayed(Data("x".utf8)) }
    }
}

@Suite struct MediaDedupeTests {
    let p = MediaImport.Parsed(title: "  [synthetic] Song A ", creator: "X", startedAt: utc(2026, 10, 31, 13, 11, 20), durationSec: 200)

    @Test func keyIsStableAndNormalised() {
        let k = MediaImport.dedupeKey(.spotify, p)
        #expect(k == MediaImport.dedupeKey(.spotify, p))
        #expect(k.hasPrefix("spotify|[synthetic] song a|"))
        let shouting = MediaImport.Parsed(title: "[SYNTHETIC] SONG A", creator: nil, startedAt: utc(2026, 10, 31, 13, 11, 10), durationSec: nil)
        #expect(MediaImport.dedupeKey(.spotify, shouting) == k)          // case, spaces, creator, seconds within the minute
    }

    @Test func differentSourceOrMinuteDiffers() {
        let k = MediaImport.dedupeKey(.spotify, p)
        #expect(MediaImport.dedupeKey(.youtube, p) != k)
        let later = MediaImport.Parsed(title: p.title, creator: nil, startedAt: p.startedAt.addingTimeInterval(120), durationSec: nil)
        #expect(MediaImport.dedupeKey(.spotify, later) != k)
    }

    @Test func modelUsesTheSameKeyAndIsNeverAIEligible() {
        let m = MediaItem(source: .youtube, title: p.title, creator: p.creator, startedAt: p.startedAt, durationSec: nil)
        #expect(m.dedupeKey == MediaImport.dedupeKey(.youtube, p))
        #expect(m.source == .youtube && m.source.type == .video && MediaSource.spotify.type == .music)
        #expect(!m.aiEligible)
        #expect(MediaSource.allCases.map(\.label) == ["Spotify", "Netflix", "YouTube"])
    }
}

@Suite struct MediaWeekTests {
    typealias Item = (source: MediaSource, title: String, creator: String?, startedAt: Date, durationSec: Double?)

    // Week Monday 2026-10-26 .. Sunday 2026-11-01, UTC, day starts at 04:00. [synthetic]
    static let items: [Item] = [
        (.spotify, "[synthetic] Song A", "[synthetic] Artist", utc(2026, 10, 26, 10), 200),
        (.spotify, "[synthetic] Song A", nil, utc(2026, 10, 26, 11), 200),
        (.spotify, "[synthetic] song a", "[synthetic] Artist", utc(2026, 10, 27, 10), 200),
        (.spotify, "[synthetic] Song B", "[synthetic] Artist", utc(2026, 10, 27, 12), 240),
        (.netflix, "[synthetic] Show X", nil, utc(2026, 10, 27, 21), 3600),
        (.netflix, "[synthetic] Show Y", nil, utc(2026, 10, 28, 22), nil),           // 45 min default
        (.netflix, "[synthetic] Show X", nil, utc(2026, 10, 28, 1, 30), 1800),       // late night of Tue 27th
        (.youtube, "[synthetic] Vid 1", "[synthetic] Chan", utc(2026, 10, 29, 2), nil),   // 10 min default, late night of Wed 28th
        (.youtube, "[synthetic] Vid 2", nil, utc(2026, 10, 29, 15), nil),
        (.youtube, "[synthetic] Vid 3", nil, utc(2026, 11, 2, 2), nil),              // Sun 1 Nov by the anchored day
        // Outside the week:
        (.netflix, "[synthetic] Before", nil, utc(2026, 10, 26, 3), 3600),           // Sun 25th by the anchored day
        (.spotify, "[synthetic] After", nil, utc(2026, 11, 2, 5), 200),              // Mon 2 Nov
    ]

    func summary(_ day: AnchoredDay = AnchoredDay(year: 2026, month: 10, day: 29)) -> MediaWeek.Summary {
        MediaWeek.summary(Self.items, weekContaining: day, dayStartHour: 4, timeZone: UTCZ)
    }

    @Test func weekStartsMondayFromAnyDayInIt() {
        let monday = AnchoredDay(year: 2026, month: 10, day: 26)
        for d in 26...31 { #expect(summary(AnchoredDay(year: 2026, month: 10, day: d)).weekStart == monday) }
        #expect(summary(AnchoredDay(year: 2026, month: 11, day: 1)).weekStart == monday)
        #expect(summary(AnchoredDay(year: 2026, month: 11, day: 2)).weekStart == AnchoredDay(year: 2026, month: 11, day: 2))
    }

    @Test func hoursAndCounts() {
        let s = summary()
        #expect(abs(s.hoursBySource[.spotify]! - 840.0 / 3600) < 1e-9)          // 200+200+200+240 s, known lengths
        #expect(abs(s.hoursBySource[.netflix]! - 2.25) < 1e-9)                  // 1 h + 45 min default + 30 min
        #expect(abs(s.hoursBySource[.youtube]! - 0.5) < 1e-9)                   // 3 x 10 min default
        #expect(s.itemsBySource == [.spotify: 4, .netflix: 3, .youtube: 3])
        #expect(s.totalItems == 10)
    }

    @Test func lateNight() {
        let s = summary()
        // 01:30 Netflix (30 min) + 02:00 YouTube (10) + 02:00 YouTube (10), all 00:00-05:00.
        #expect(abs(s.lateNightHours - (0.5 + 10.0 / 60 + 10.0 / 60)) < 1e-9)
        #expect(s.lateNightNights == 3)
    }

    @Test func oneThirtyBelongsToThePreviousAnchoredDay() {
        let s = summary()
        let tue = s.byDay.first { $0.day == AnchoredDay(year: 2026, month: 10, day: 27) }!
        // Tue: Song A (200) + Song B (240) + Show X (3600) + the 01:30 play from the early hours of Wed (1800).
        #expect(abs(tue.hours - 5840.0 / 3600) < 1e-9)
        let wed = s.byDay.first { $0.day == AnchoredDay(year: 2026, month: 10, day: 28) }!
        #expect(abs(wed.hours - 3300.0 / 3600) < 1e-9)                          // Show Y 45 min + 02:00 Vid 1 10 min
    }

    @Test func byDayHasSevenMondayFirst() {
        let s = summary()
        #expect(s.byDay.count == 7)
        #expect(s.byDay.map(\.day.day) == [26, 27, 28, 29, 30, 31, 1])
        #expect(abs(s.byDay[0].hours - 400.0 / 3600) < 1e-9)
        #expect(s.byDay[4].hours == 0 && s.byDay[5].hours == 0)
        #expect(abs(s.byDay[6].hours - 10.0 / 60) < 1e-9)
        #expect(abs(s.byDay.map(\.hours).reduce(0, +) - s.totalHours) < 1e-9)
    }

    @Test func replaysAreThreeOrMoreIgnoringCase() {
        let s = summary()
        #expect(s.replays.count == 1)
        #expect(s.replays[0].title == "[synthetic] Song A" && s.replays[0].count == 3)
        #expect(s.replays[0].creator == "[synthetic] Artist")
    }

    @Test func replaysCappedAtFiveAndOrdered() {
        var items: [Item] = []
        for n in 1...7 { for k in 0..<(2 + n) { items.append((.spotify, "[synthetic] T\(n)", nil, utc(2026, 10, 26, 8, k), 180)) } }
        let s = MediaWeek.summary(items, weekContaining: AnchoredDay(year: 2026, month: 10, day: 26), dayStartHour: 4, timeZone: UTCZ)
        #expect(s.replays.map(\.title) == ["[synthetic] T7", "[synthetic] T6", "[synthetic] T5", "[synthetic] T4", "[synthetic] T3"])
        #expect(s.replays.map(\.count) == [9, 8, 7, 6, 5])
    }

    @Test func topThreePerSource() {
        let s = summary()
        #expect(s.top[.spotify]!.map(\.title) == ["[synthetic] Song A", "[synthetic] Song B"])
        #expect(s.top[.spotify]!.map(\.count) == [3, 1])
        #expect(s.top[.netflix]!.map(\.title) == ["[synthetic] Show X", "[synthetic] Show Y"])
        #expect(s.top[.youtube]!.count == 3 && s.top[.youtube]!.map(\.count) == [1, 1, 1])
        let many = MediaWeek.summary((1...5).map { n in (.youtube, "[synthetic] V\(n)", nil, utc(2026, 10, 26, 8 + n), nil) },
                                     weekContaining: AnchoredDay(year: 2026, month: 10, day: 26), dayStartHour: 4, timeZone: UTCZ)
        #expect(many.top[.youtube]!.count == 3 && many.top[.spotify] == nil)
    }

    @Test func dayStartHourChangesWhichDay() {
        // 02:00 Tue with dayStartHour 0 stays on Tue; with 4 it is Mon's.
        let item: [Item] = [(.netflix, "[synthetic] A", nil, utc(2026, 10, 27, 2), 3600)]
        let early = MediaWeek.summary(item, weekContaining: AnchoredDay(year: 2026, month: 10, day: 27), dayStartHour: 0, timeZone: UTCZ)
        #expect(early.byDay[1].hours == 1 && early.byDay[0].hours == 0 && early.lateNightNights == 1)
        let late = MediaWeek.summary(item, weekContaining: AnchoredDay(year: 2026, month: 10, day: 27), dayStartHour: 4, timeZone: UTCZ)
        #expect(late.byDay[0].hours == 1 && late.byDay[1].hours == 0)
    }

    @Test func localTimeZoneDecidesLateNight() {
        // 17:30 UTC is 02:30 in Tokyo the next day.
        let item: [Item] = [(.netflix, "[synthetic] A", nil, utc(2026, 10, 27, 17, 30), 3600)]
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let s = MediaWeek.summary(item, weekContaining: AnchoredDay(year: 2026, month: 10, day: 27), dayStartHour: 4, timeZone: tokyo)
        #expect(s.lateNightHours == 1 && s.lateNightNights == 1)
        #expect(s.byDay[1].hours == 1)                                            // Tue the 27th, by the anchored day
        #expect(MediaWeek.summary(item, weekContaining: AnchoredDay(year: 2026, month: 10, day: 27), dayStartHour: 4, timeZone: UTCZ).lateNightHours == 0)
    }

    @Test func describeMatchesTheExample() {
        // 6 h video, ~3 h music, 2 late nights. [synthetic]
        var items: [Item] = []
        items += (0..<6).map { (.netflix, "[synthetic] N\($0)", nil, utc(2026, 10, 26 + $0 % 3, 20), 3600) }
        items += (0..<3).map { (.spotify, "[synthetic] S\($0)", nil, utc(2026, 10, 26, 8 + $0), 3600) }
        items += [(.spotify, "[synthetic] L1", nil, utc(2026, 10, 28, 1), 1), (.spotify, "[synthetic] L2", nil, utc(2026, 10, 29, 1), 1)]
        let s = MediaWeek.summary(items, weekContaining: AnchoredDay(year: 2026, month: 10, day: 26), dayStartHour: 4, timeZone: UTCZ)
        #expect(MediaWeek.describe(s) == "About 9 hours this week: 6 h video, 3 h music. Media ran past midnight on 2 nights.")
    }

    @Test func describeEdgeCases() {
        let day = AnchoredDay(year: 2026, month: 10, day: 26)
        #expect(MediaWeek.describe(MediaWeek.summary([], weekContaining: day, dayStartHour: 4, timeZone: UTCZ)) == "No media this week.")
        let one: [Item] = [(.netflix, "[synthetic] A", nil, utc(2026, 10, 26, 20), 3600), (.spotify, "[synthetic] B", nil, utc(2026, 10, 26, 9), 600)]
        #expect(MediaWeek.describe(MediaWeek.summary(one, weekContaining: day, dayStartHour: 4, timeZone: UTCZ))
                == "About 1 hour this week: 1 h video, under 1 h music.")
        let tiny: [Item] = [(.spotify, "[synthetic] B", nil, utc(2026, 10, 26, 9), 600)]
        #expect(MediaWeek.describe(MediaWeek.summary(tiny, weekContaining: day, dayStartHour: 4, timeZone: UTCZ)) == "Under an hour of media this week.")
    }

    @Test func describeNeverMoralises() {
        let day = AnchoredDay(year: 2026, month: 10, day: 26)
        let heavy: [Item] = (0..<60).map { (.netflix, "[synthetic] H", nil, utc(2026, 10, 26 + $0 % 7, $0 % 3 + 1, $0), 3600) }
        let sets: [[Item]] = [[], Self.items, heavy]
        let banned = ["too much", "should", "addict", "binge", "excess", "unhealthy", "problem", "careful", "try to", "cut back", "worry", "!"]
        for items in sets {
            let text = MediaWeek.describe(MediaWeek.summary(items, weekContaining: day, dayStartHour: 4, timeZone: UTCZ)).lowercased()
            for word in banned { #expect(!text.contains(word), "\"\(word)\" in \"\(text)\"") }
        }
    }
}

@Suite struct MediaStorageTests {
    @Test func backupRestoreSkipsSameDedupeKeyUnderAnotherId() throws {
        let a = ModelContext(try exportContainer())
        let one = MediaItem(source: .spotify, title: "[synthetic] Song", creator: "[synthetic] Artist", startedAt: t0, durationSec: 200)
        one.deviceId = "dev-1"
        a.insert(one); try a.save()
        let archive = try BackupArchive.make(context: a)

        // Another device already imported the same play under its own id.
        let b = ModelContext(try exportContainer())
        let twin = MediaItem(source: .spotify, title: "[synthetic] SONG", creator: nil, startedAt: t0.addingTimeInterval(5), durationSec: nil)
        b.insert(twin); try b.save()
        let summary = try BackupArchive.restore(archive, into: b)
        #expect(summary.added["MediaItem"] == nil && summary.skipped == 1)
        #expect(try b.fetchCount(FetchDescriptor<MediaItem>()) == 1)

        // A fresh store gets it once, and a second restore adds nothing.
        let c = ModelContext(try exportContainer())
        #expect(try BackupArchive.restore(archive, into: c).added["MediaItem"] == 1)
        #expect(try BackupArchive.restore(archive, into: c).added.isEmpty)
    }

    @Test func demoMediaNotBackedUp() throws {
        let c = ModelContext(try exportContainer())
        let m = MediaItem(source: .netflix, title: "[synthetic] Demo", creator: nil, startedAt: t0, durationSec: nil)
        m.deviceId = "demo"
        c.insert(m); try c.save()
        let files = try ZipReader.entries(BackupArchive.make(context: c))
        let rows = try JSONSerialization.jsonObject(with: files["mediaItems.json"]!) as! [Any]
        #expect(rows.isEmpty)
    }

    @Test func spreadsheetSheetMarksDisplayOnly() throws {
        let c = ModelContext(try exportContainer())
        seedEverything(c)
        let sheet = try #require(try SpreadsheetExport.sheets(context: c, options: ExportOptions()).first { $0.name == "Media" })
        #expect(sheet.header == ["Source", "Title", "Creator", "Started", "Length (min, only where known)"])
        #expect(sheet.rows.count == 1)
        #expect(sheet.rows[0][0] == .text("Netflix (display only)"))
        #expect(sheet.rows[0][4] == .number(2530.0 / 60))
        // Media is her data in her own spreadsheet; it still goes out when body sheets are off.
        #expect(try SpreadsheetExport.sheets(context: c, options: ExportOptions(includeBody: false)).contains { $0.name == "Media" })
    }

    /// CLAUDE.md #6: media is display-only. Only the model, its backup and the spreadsheet may mention it;
    /// statistics, outlook, patterns, listen and the language model must not.
    @Test func onlyAllowedFilesTouchMediaItems() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/AiHeartCore")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        #expect(files.count > 10)
        let allowed: Set<String> = ["Media.swift", "Models.swift", "Backup.swift", "ExportData.swift"]
        for f in files where !allowed.contains(f.lastPathComponent) {
            let text = try String(contentsOf: f, encoding: .utf8)
            #expect(!text.contains("MediaItem") && !text.contains("MediaWeek"), "\(f.lastPathComponent) reads media")
        }
    }
}
