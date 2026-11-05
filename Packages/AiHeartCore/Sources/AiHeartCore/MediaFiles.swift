import Foundation

/// Picking the right files from a data download (owner, 2026-11-02: the Netflix import failed).
/// Netflix's "Download your personal information" and Spotify's "Download your data" arrive as
/// compressed ZIPs; the importer used to accept only a bare CSV or JSON. Now she can share either.
extension MediaImport {
    /// True for names inside a download that hold history for this source.
    public static func isHistoryFile(_ source: MediaSource, name: String) -> Bool {
        let file = (name as NSString).lastPathComponent.lowercased()
        switch source {
        case .netflix:
            return file == "viewingactivity.csv" || (file.hasPrefix("netflixviewinghistory") && file.hasSuffix(".csv"))
        case .spotify:
            guard file.hasSuffix(".json") else { return false }
            // Account data: StreamingHistory_music_0.json (older: StreamingHistory0.json). Extended:
            // Streaming_History_Audio_2025.json. Podcast and video files are left out.
            if file.hasPrefix("streaminghistory_music") || file.hasPrefix("streaming_history_audio") { return true }
            let rest = file.dropFirst("streaminghistory".count).dropLast(".json".count)
            return file.hasPrefix("streaminghistory") && !rest.isEmpty && rest.allSatisfy(\.isNumber)
        case .youtube:
            return file == "watch-history.json"
        }
    }

    /// The history files in what she picked: the file itself, or the matching files inside a ZIP.
    public static func historyFiles(_ source: MediaSource, data: Data) throws -> [Data] {
        guard ZipReader.isZip(data) else { return [data] }
        let files = try ZipReader.entries(data) { isHistoryFile(source, name: $0) }
        guard !files.isEmpty else { throw MediaImportError.unrecognizedFormat }
        return files.keys.sorted().map { files[$0]! }
    }

    /// Profile names in a Netflix "Download all" ViewingActivity.csv, most rows first.
    /// Empty for the simple per-profile export, which has no profile column.
    public static func netflixProfiles(_ data: Data) -> [String] {
        let table = CSV.parse(data)
        guard let header = table.first,
              let col = header.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).firstIndex(of: "profile name")
        else { return [] }
        var counts: [String: Int] = [:]
        for row in table.dropFirst() where col < row.count {
            let p = row[col].trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty { counts[p, default: 0] += 1 }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    /// Parses every history file. A file that is not history is skipped; if none parse, it fails.
    public static func parse(_ source: MediaSource, files: [Data], netflixProfile: String? = nil) throws -> [Parsed] {
        var out: [Parsed] = []
        var any = false
        for f in files {
            let items: [Parsed]?
            switch source {
            case .netflix: items = try? netflix(f, profile: netflixProfile)
            case .spotify: items = try? spotifyExport(f)
            case .youtube: items = try? youtube(f)
            }
            if let items { any = true; out += items }
        }
        guard any else { throw MediaImportError.unrecognizedFormat }
        return out
    }
}
