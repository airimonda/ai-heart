import Foundation
import SwiftData

// Media (M18, docs/14). Spotify, Netflix and YouTube only. Everything here is DISPLAY-ONLY
// (CLAUDE.md #6): `aiEligible` is false on every row, and nothing in statistics, the outlook,
// embeddings or any LLM prompt may read MediaItem. Parsing happens on device; nothing is uploaded.
// Weekly framing only (docs/14): no live counters, no judgement about content or amount.

public enum MediaSource: String, CaseIterable, Sendable {
    case spotify, netflix, youtube

    public var label: String {
        switch self {
        case .spotify: "Spotify"
        case .netflix: "Netflix"
        case .youtube: "YouTube"
        }
    }

    public var type: MediaType { self == .spotify ? .music : .video }
}

public enum MediaType: String, Sendable { case music, video }

@Model
public final class MediaItem {
    public var syncId: UUID = UUID()
    public var sourceRaw: String = MediaSource.spotify.rawValue
    @Attribute(.allowsCloudEncryption) public var title: String = ""
    /// Artist or channel. Nil for Netflix.
    @Attribute(.allowsCloudEncryption) public var creator: String?
    public var startedAt: Date = Date()
    /// Known for Spotify (track length) and the Netflix "Download all" export.
    public var durationSec: Double?
    /// Spotify artist IDs (comma-separated) and their genres, for the vibe line only.
    @Attribute(.allowsCloudEncryption) public var artistIds: String?
    @Attribute(.allowsCloudEncryption) public var genres: String?
    /// Always false for now: Spotify by its terms; Netflix and YouTube until their terms are verified.
    public var aiEligible: Bool = false
    /// `MediaImport.dedupeKey`: source | lowercased title | start rounded to the minute.
    public var dedupeKey: String = ""
    public var deviceId: String = ""

    public init(source: MediaSource, title: String, creator: String?, startedAt: Date, durationSec: Double?) {
        self.sourceRaw = source.rawValue
        self.title = title
        self.creator = creator
        self.startedAt = startedAt
        self.durationSec = durationSec
        self.aiEligible = false
        self.dedupeKey = MediaImport.dedupeKey(source, MediaImport.Parsed(title: title, creator: creator, startedAt: startedAt, durationSec: durationSec))
    }

    public var source: MediaSource { MediaSource(rawValue: sourceRaw) ?? .spotify }
}

public enum MediaImportError: Error, Equatable {
    /// The file is not the shape we expect (wrong header, not JSON, not the right JSON).
    case unrecognizedFormat
}

public enum MediaImport {
    public struct Parsed: Sendable, Equatable {
        public let title: String
        public let creator: String?
        public let startedAt: Date
        public let durationSec: Double?
        /// Spotify artist IDs, for the genre lookup (live fetch only).
        public var artistIds: [String] = []

        public init(title: String, creator: String?, startedAt: Date, durationSec: Double?) {
            self.title = title
            self.creator = creator
            self.startedAt = startedAt
            self.durationSec = durationSec
        }
    }

    /// source | lowercased, trimmed title | start as whole minutes since 1970 (rounded).
    public static func dedupeKey(_ source: MediaSource, _ p: Parsed) -> String {
        let minute = Int((p.startedAt.timeIntervalSince1970 / 60).rounded())
        return "\(source.rawValue)|\(p.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(minute)"
    }

    // MARK: Netflix

    /// Netflix viewing activity, either format:
    /// (a) the simple "Viewing activity" CSV (`Title,Date`): dates like 10/31/26 or 31/10/2026,
    ///     no time, so noon in `timeZone`. A first number above 12 means day-first, a second
    ///     number above 12 means month-first; if neither occurs anywhere, month-first (Netflix's US default).
    /// (b) the "Download all" ViewingActivity.csv (`Profile Name,Start Time,Duration,Attributes,Title,...`),
    ///     Start Time in UTC, Duration `HH:MM:SS`.
    /// Skips autoplayed rows shorter than 2 minutes and trailers/hooks (a "Supplemental Video Type").
    /// `profile` keeps only that profile (format b; case-insensitive).
    public static func netflix(_ data: Data, profile: String? = nil, timeZone: TimeZone = .current) throws -> [Parsed] {
        let table = CSV.parse(data)
        guard let header = table.first else { throw MediaImportError.unrecognizedFormat }
        let cols = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        func col(_ name: String) -> Int? { cols.firstIndex(of: name) }
        guard let titleCol = col("title") else { throw MediaImportError.unrecognizedFormat }
        let body = table.dropFirst()
        func cell(_ row: [String], _ i: Int?) -> String {
            guard let i, i < row.count else { return "" }
            return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let startCol = col("start time") {
            let profileCol = col("profile name"), durCol = col("duration"), attrCol = col("attributes")
            let supCol = col("supplemental video type")
            let wanted = profile?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var out: [Parsed] = []
            for row in body {
                let title = cell(row, titleCol)
                guard !title.isEmpty else { continue }
                if let wanted, cell(row, profileCol).lowercased() != wanted { continue }
                if !cell(row, supCol).isEmpty { continue }
                guard let start = parseUTC(cell(row, startCol)) else { continue }
                let dur = parseDuration(cell(row, durCol))
                if cell(row, attrCol).localizedCaseInsensitiveContains("autoplayed"), (dur ?? 0) < 120 { continue }
                out.append(Parsed(title: title, creator: nil, startedAt: start, durationSec: (dur ?? 0) > 0 ? dur : nil))
            }
            return out
        }

        guard let dateCol = col("date") else { throw MediaImportError.unrecognizedFormat }
        let rows = body.compactMap { row -> (String, [Int])? in
            let title = cell(row, titleCol)
            let nums = splitDate(cell(row, dateCol))
            guard !title.isEmpty, let nums else { return nil }
            return (title, nums)
        }
        // File-wide hint for rows where both numbers are 12 or less.
        let dayFirstSeen = rows.contains { $0.1[0] > 12 && $0.1[0] <= 31 && $0.1[2] > 31 }
        let monthFirstSeen = rows.contains { $0.1[1] > 12 && $0.1[0] <= 12 && $0.1[2] > 31 }
        let defaultDayFirst = dayFirstSeen && !monthFirstSeen
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var out: [Parsed] = []
        for (title, n) in rows {
            let y: Int, m: Int, d: Int
            if n[0] > 31 {                                  // 2026-10-31
                (y, m, d) = (n[0], n[1], n[2])
            } else {
                y = n[2] < 100 ? 2000 + n[2] : n[2]
                let dayFirst = n[0] > 12 ? true : (n[1] > 12 ? false : defaultDayFirst)
                (m, d) = dayFirst ? (n[1], n[0]) : (n[0], n[1])
            }
            guard let noon = cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12)),
                  cal.component(.month, from: noon) == m, cal.component(.day, from: noon) == d else { continue }
            out.append(Parsed(title: title, creator: nil, startedAt: noon, durationSec: nil))
        }
        return out
    }

    /// "10/31/26", "31.10.2026", "10-31-2026" or "2026-10-31" as three numbers; nil if not that shape.
    private static func splitDate(_ s: String) -> [Int]? {
        let parts = s.split(whereSeparator: { "/.-".contains($0) }).map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.map { $0! }
    }

    private static func parseUTC(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: s)
    }

    private static func parseDuration(_ s: String) -> Double? {
        let p = s.split(separator: ":").map { Double($0) }
        guard p.count == 3, p.allSatisfy({ $0 != nil }) else { return nil }
        return p[0]! * 3600 + p[1]! * 60 + p[2]!
    }

    // MARK: YouTube

    /// Google Takeout `watch-history.json`. Strips "Watched " (also Japanese "…を視聴しました" and
    /// Tagalog "Pinanood ang "). Skips ads ("From Google Ads" in `details`) and entries with no
    /// `titleUrl` (removed videos). Duration is not in the file, so nil.
    public static func youtube(_ data: Data) throws -> [Parsed] {
        guard let json = try? JSONSerialization.jsonObject(with: data), let items = json as? [[String: Any]] else {
            throw MediaImportError.unrecognizedFormat
        }
        var out: [Parsed] = []
        for item in items {
            guard let raw = item["title"] as? String, let url = item["titleUrl"] as? String, !url.isEmpty,
                  let time = (item["time"] as? String).flatMap(parseISO) else { continue }
            if let details = item["details"] as? [[String: Any]],
               details.contains(where: { ($0["name"] as? String)?.localizedCaseInsensitiveContains("From Google Ads") == true }) { continue }
            let title = stripWatched(raw)
            guard !title.isEmpty else { continue }
            let channel = (item["subtitles"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.first
            out.append(Parsed(title: title, creator: channel?.isEmpty == false ? channel : nil, startedAt: time, durationSec: nil))
        }
        return out
    }

    private static func stripWatched(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Watched ", "Pinanood ang "] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count)); break
        }
        if t.hasSuffix("を視聴しました") { t = String(t.dropLast("を視聴しました".count)) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Spotify

    /// `GET /v1/me/player/recently-played`. `played_at` is when the track ended, so
    /// startedAt = played_at minus the track length.
    /// Spotify "Download your data" export, her own data (owner, 2026-11-02): either
    /// StreamingHistory_music_N.json ([{endTime "yyyy-MM-dd HH:mm" UTC, artistName, trackName, msPlayed}])
    /// or the extended Streaming_History_Audio_*.json ([{ts ISO8601, master_metadata_track_name,
    /// master_metadata_album_artist_name, ms_played}]). Plays under 30 s are skipped; podcasts without
    /// a track name are skipped.
    public static func spotifyExport(_ data: Data) throws -> [Parsed] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw MediaImportError.unrecognizedFormat }
        let iso = ISO8601DateFormatter()
        let short = DateFormatter()
        short.locale = Locale(identifier: "en_US_POSIX"); short.timeZone = TimeZone(identifier: "UTC"); short.dateFormat = "yyyy-MM-dd HH:mm"
        var out: [Parsed] = []
        var recognised = false
        for r in arr {
            if let end = r["endTime"] as? String, let name = r["trackName"] as? String {
                recognised = true
                let ms = (r["msPlayed"] as? Double) ?? Double(r["msPlayed"] as? Int ?? 0)
                guard ms >= 30_000, let e = short.date(from: end), !name.isEmpty else { continue }
                out.append(Parsed(title: name, creator: r["artistName"] as? String, startedAt: e.addingTimeInterval(-ms / 1000), durationSec: ms / 1000))
            } else if let ts = r["ts"] as? String {
                recognised = true
                let ms = (r["ms_played"] as? Double) ?? Double(r["ms_played"] as? Int ?? 0)
                guard ms >= 30_000, let e = iso.date(from: ts), let name = r["master_metadata_track_name"] as? String, !name.isEmpty else { continue }
                out.append(Parsed(title: name, creator: r["master_metadata_album_artist_name"] as? String, startedAt: e.addingTimeInterval(-ms / 1000), durationSec: ms / 1000))
            }
        }
        guard recognised || arr.isEmpty else { throw MediaImportError.unrecognizedFormat }
        return out
    }

    public static func spotifyRecentlyPlayed(_ data: Data) throws -> [Parsed] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { throw MediaImportError.unrecognizedFormat }
        var out: [Parsed] = []
        for item in items {
            guard let track = item["track"] as? [String: Any], let name = track["name"] as? String, !name.isEmpty,
                  let playedAt = (item["played_at"] as? String).flatMap(parseISO) else { continue }
            let artists = (track["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.filter { !$0.isEmpty } ?? []
            let ms = (track["duration_ms"] as? NSNumber)?.doubleValue
            let dur = ms.map { $0 / 1000 }
            var p = Parsed(title: name, creator: artists.isEmpty ? nil : artists.joined(separator: ", "),
                           startedAt: playedAt.addingTimeInterval(-(dur ?? 0)), durationSec: dur)
            p.artistIds = (track["artists"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
            out.append(p)
        }
        return out
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// Small RFC 4180 reader: quoted fields, commas and newlines inside quotes, `""` escapes, BOM, CRLF.
enum CSV {
    static func parse(_ data: Data) -> [[String]] {
        var text = String(decoding: data, as: UTF8.self)
        if text.unicodeScalars.first == "\u{FEFF}" { text.unicodeScalars.removeFirst() }
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false
        let s = Array(text.unicodeScalars)
        var i = 0
        func endRow() {
            row.append(field); field = ""
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }
        while i < s.count {
            let c = s[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < s.count, s[i + 1] == "\"" { field.unicodeScalars.append("\""); i += 1 } else { inQuotes = false }
                } else { field.unicodeScalars.append(c) }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                row.append(field); field = ""
            } else if c == "\r" || c == "\n" {
                if c == "\r", i + 1 < s.count, s[i + 1] == "\n" { i += 1 }
                endRow()
            } else { field.unicodeScalars.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}

// MARK: Weekly summary

public enum MediaWeek {
    /// Defaults used when a length is unknown (estimates, shown as "about"):
    /// Spotify track 3.5 min, Netflix title 45 min, YouTube video 10 min.
    public static let defaultMinutes: [MediaSource: Double] = [.spotify: 3.5, .netflix: 45, .youtube: 10]

    public struct Summary: Sendable {
        public let weekStart: AnchoredDay
        /// Estimate: known durations where there are any, else the defaults above. All three sources are present.
        public let hoursBySource: [MediaSource: Double]
        /// All three sources are present.
        public let itemsBySource: [MediaSource: Int]
        /// Starts between 00:00 and 05:00 local.
        public let lateNightHours: Double
        /// Distinct nights with late-night media. A night is named for the evening it began.
        public let lateNightNights: Int
        /// The same title (per source) 3 or more times in the week, most first, at most 5.
        public let replays: [(title: String, creator: String?, count: Int)]
        /// Top 3 per source by count, then title. Only sources with items appear.
        public let top: [MediaSource: [(title: String, count: Int)]]
        /// Seven entries, Monday first.
        public let byDay: [(day: AnchoredDay, hours: Double)]

        public var totalHours: Double { hoursBySource.values.reduce(0, +) }
        public var totalItems: Int { itemsBySource.values.reduce(0, +) }
    }

    public static func summary(
        _ items: [(source: MediaSource, title: String, creator: String?, startedAt: Date, durationSec: Double?)],
        weekContaining day: AnchoredDay, dayStartHour: Int, timeZone: TimeZone, rolling: Bool = false
    ) -> Summary {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        // Monday-start week of the anchored day (noon avoids DST edges), or with `rolling`
        // the 7 days ending on that day (owner, 2026-11-02).
        let noon = day.date(in: cal)
        let sinceMonday = rolling ? 6 : (cal.component(.weekday, from: noon) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -sinceMonday, to: noon) ?? noon
        let days: [AnchoredDay] = (0..<7).map { n in
            let d = cal.date(byAdding: .day, value: n, to: monday) ?? monday
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return AnchoredDay(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
        }
        let inWeek = Set(days)

        var hours: [MediaSource: Double] = Dictionary(uniqueKeysWithValues: MediaSource.allCases.map { ($0, 0) })
        var counts: [MediaSource: Int] = Dictionary(uniqueKeysWithValues: MediaSource.allCases.map { ($0, 0) })
        var dayHours: [AnchoredDay: Double] = [:]
        var lateHours = 0.0
        var nights = Set<AnchoredDay>()
        struct Key: Hashable { let source: MediaSource; let title: String }
        var groups: [Key: (title: String, creator: String?, count: Int)] = [:]

        for it in items {
            let anchored = DayAnchor.day(for: it.startedAt, timeZone: timeZone, dayStartHour: dayStartHour)
            guard inWeek.contains(anchored) else { continue }
            let h = ((it.durationSec.map { $0 / 60 } ?? defaultMinutes[it.source] ?? 0)) / 60
            hours[it.source, default: 0] += h
            counts[it.source, default: 0] += 1
            dayHours[anchored, default: 0] += h
            if cal.component(.hour, from: it.startedAt) < 5 {
                lateHours += h
                // Named for the evening it began, whatever the day-start hour is.
                nights.insert(DayAnchor.day(for: it.startedAt, timeZone: timeZone, dayStartHour: max(dayStartHour, 5)))
            }
            let key = Key(source: it.source, title: it.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            var g = groups[key] ?? (it.title, it.creator, 0)
            g.count += 1
            if g.creator == nil { g.creator = it.creator }
            groups[key] = g
        }

        func order(_ a: (title: String, count: Int), _ b: (title: String, count: Int)) -> Bool {
            a.count != b.count ? a.count > b.count : a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        let replays = groups.values.filter { $0.count >= 3 }
            .sorted { order(($0.title, $0.count), ($1.title, $1.count)) }
            .prefix(5).map { (title: $0.title, creator: $0.creator, count: $0.count) }
        var top: [MediaSource: [(title: String, count: Int)]] = [:]
        for source in MediaSource.allCases {
            let rows = groups.filter { $0.key.source == source }.map { (title: $0.value.title, count: $0.value.count) }
            if !rows.isEmpty { top[source] = Array(rows.sorted(by: order).prefix(3)) }
        }

        return Summary(
            weekStart: days[0], hoursBySource: hours, itemsBySource: counts, lateNightHours: lateHours,
            lateNightNights: nights.count, replays: Array(replays), top: top,
            byDay: days.map { (day: $0, hours: dayHours[$0] ?? 0) })
    }

    /// Counts only, no judgement. Example: "About 9 hours this week: 6 h video, 3 h music.
    /// Media ran past midnight on 2 nights." Never moralise.
    public static func describe(_ s: Summary) -> String {
        guard s.totalItems > 0 else { return "No media this week." }
        func h(_ x: Double) -> String { x >= 0.5 ? "\(Int(x.rounded())) h" : "under 1 h" }
        let video = (s.hoursBySource[.netflix] ?? 0) + (s.hoursBySource[.youtube] ?? 0)
        let music = s.hoursBySource[.spotify] ?? 0
        let total = s.totalHours
        var line = total < 0.5 ? "Under an hour of media this week."
            : "About \(Int(total.rounded())) \(Int(total.rounded()) == 1 ? "hour" : "hours") this week"
        let parts = [(video, "video"), (music, "music")].filter { $0.0 > 0 }.map { "\(h($0.0)) \($0.1)" }
        if total >= 0.5 { line += parts.isEmpty ? "." : ": " + parts.joined(separator: ", ") + "." }
        if s.lateNightNights > 0 {
            line += " Media ran past midnight on \(s.lateNightNights) \(s.lateNightNights == 1 ? "night" : "nights")."
        }
        return line
    }
}
