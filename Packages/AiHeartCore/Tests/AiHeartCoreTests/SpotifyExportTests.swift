import Foundation
import Testing
@testable import AiHeartCore

// Synthetic export rows only.

@Suite struct SpotifyExportTests {
    @Test func bothFormats() throws {
        let basic = """
        [{"endTime":"2026-10-31 21:15","artistName":"[synthetic] Artist","trackName":"[synthetic] Song","msPlayed":180000},
         {"endTime":"2026-10-31 21:16","artistName":"[synthetic] Artist","trackName":"[synthetic] Skip","msPlayed":4000}]
        """
        let a = try MediaImport.spotifyExport(Data(basic.utf8))
        #expect(a.count == 1 && a[0].durationSec == 180 && a[0].creator == "[synthetic] Artist")
        let ext = """
        [{"ts":"2026-10-31T21:15:00Z","master_metadata_track_name":"[synthetic] Song","master_metadata_album_artist_name":"[synthetic] A","ms_played":200000},
         {"ts":"2026-10-31T22:00:00Z","master_metadata_track_name":null,"ms_played":900000}]
        """
        let b = try MediaImport.spotifyExport(Data(ext.utf8))
        #expect(b.count == 1 && b[0].title == "[synthetic] Song")
        #expect(throws: MediaImportError.self) { try MediaImport.spotifyExport(Data("[{\"x\":1}]".utf8)) }
    }
}
