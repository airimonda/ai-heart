import Foundation
import Testing
@testable import AiHeartCore

// Synthetic files only.

/// A ZIP with deflated entries and a data descriptor, the way Netflix and Spotify build theirs.
func deflatedZip(_ files: [(String, Data)]) -> Data {
    var out = Data(), central = Data()
    func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
    func le32(_ v: Int) -> Data { Data((0..<4).map { UInt8(v >> (8 * $0) & 0xFF) }) }
    for (name, body) in files {
        let comp = ZipReader.deflate(body)
        let crc = Int(CRC32.checksum(body))
        let offset = out.count
        let n = Data(name.utf8)
        // Local header with sizes zeroed (bit 3), then the data descriptor.
        let local: [Data] = [le32(0x0403_4B50), le16(20), le16(8), le16(8), le16(0), le16(0), le32(0), le32(0), le32(0),
                             le16(n.count), le16(0), n, comp, le32(0x0807_4B50), le32(crc), le32(comp.count), le32(body.count)]
        for d in local { out.append(d) }
        let entry: [Data] = [le32(0x0201_4B50), le16(20), le16(20), le16(8), le16(8), le16(0), le16(0), le32(crc), le32(comp.count),
                             le32(body.count), le16(n.count), le16(0), le16(0), le16(0), le16(0), le32(0), le32(offset), n]
        for d in entry { central.append(d) }
    }
    let cdStart = out.count
    out.append(central)
    let end: [Data] = [le32(0x0605_4B50), le16(0), le16(0), le16(files.count), le16(files.count), le32(central.count), le32(cdStart), le16(0)]
    for d in end { out.append(d) }
    return out
}

@Suite struct MediaFilesTests {
    let viewing = """
    Profile Name,Start Time,Duration,Attributes,Title,Supplemental Video Type,Device Type,Bookmark,Latest Bookmark,Country
    Me,2026-10-30 13:00:00,00:45:00,,[synthetic] Show: Episode 1,,iPhone,00:45:00,00:45:00,PH
    Me,2026-10-31 13:00:00,00:40:00,,[synthetic] Show: Episode 2,,iPhone,00:40:00,00:40:00,PH
    Kid,2026-10-31 09:00:00,00:20:00,,[synthetic] Cartoon,,TV,00:20:00,00:20:00,PH
    """

    @Test func readsNetflixFromACompressedDownload() throws {
        let zip = deflatedZip([("CONTENT_INTERACTION/ViewingActivity.csv", Data(viewing.utf8)),
                               ("CONTENT_INTERACTION/Ratings.csv", Data("Profile Name,Title\nMe,x\n".utf8))])
        #expect(ZipReader.isZip(zip))
        let files = try MediaImport.historyFiles(.netflix, data: zip)
        #expect(files.count == 1)
        #expect(MediaImport.netflixProfiles(files[0]) == ["Me", "Kid"])
        let mine = try MediaImport.parse(.netflix, files: files, netflixProfile: "Me")
        #expect(mine.map(\.title) == ["[synthetic] Show: Episode 1", "[synthetic] Show: Episode 2"])
    }

    @Test func plainCSVStillWorks() throws {
        let csv = Data("Title,Date\n\"[synthetic] Show: Episode 1\",10/31/26\n".utf8)
        let items = try MediaImport.parse(.netflix, files: MediaImport.historyFiles(.netflix, data: csv))
        #expect(items.count == 1)
        #expect(MediaImport.netflixProfiles(csv).isEmpty)
    }

    @Test func spotifyDownloadSkipsPodcastsAndVideo() throws {
        let music = #"[{"endTime":"2026-10-31 12:00","artistName":"[synthetic] A","trackName":"[synthetic] Song","msPlayed":200000}]"#
        let podcast = #"[{"endTime":"2026-10-31 13:00","podcastName":"P","episodeName":"E","msPlayed":900000}]"#
        let zip = deflatedZip([("Spotify Account Data/StreamingHistory_music_0.json", Data(music.utf8)),
                               ("Spotify Account Data/StreamingHistory_podcast_0.json", Data(podcast.utf8)),
                               ("Spotify Extended Streaming History/Streaming_History_Video_2025.json", Data("[]".utf8))])
        let files = try MediaImport.historyFiles(.spotify, data: zip)
        #expect(files.count == 1)
        #expect(try MediaImport.parse(.spotify, files: files).map(\.title) == ["[synthetic] Song"])
    }

    @Test func historyFileNames() {
        #expect(MediaImport.isHistoryFile(.spotify, name: "x/StreamingHistory0.json"))
        #expect(MediaImport.isHistoryFile(.spotify, name: "x/Streaming_History_Audio_2024-2025_3.json"))
        #expect(!MediaImport.isHistoryFile(.spotify, name: "x/StreamingHistory_podcast_0.json"))
        #expect(MediaImport.isHistoryFile(.netflix, name: "NetflixViewingHistory (1).csv"))
        #expect(MediaImport.isHistoryFile(.youtube, name: "Takeout/YouTube/history/watch-history.json"))
    }

    @Test func zipWithoutHistoryIsRejected() {
        let zip = deflatedZip([("other.txt", Data("hello".utf8))])
        #expect(throws: MediaImportError.unrecognizedFormat) { try MediaImport.historyFiles(.netflix, data: zip) }
    }
}
