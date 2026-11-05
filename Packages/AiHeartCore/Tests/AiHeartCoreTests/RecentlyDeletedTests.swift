import Foundation
import SwiftData
import Testing
@testable import AiHeartCore

// Synthetic entries only.

@Suite struct RecentlyDeletedTests {
    func make(_ c: ModelContext) -> Entry {
        let e = Entry(kind: .write, createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        e.text = "[synthetic] A morning I want to keep.\nSecond line."
        e.photoData = Data([1, 2, 3])
        var n = ReleaseNote(); n.feelings = [.calm]; e.releaseNote = n
        c.insert(e)
        try? c.save()
        return e
    }

    @Test func deleteMovesItOutOfTheJournalWithoutATombstone() throws {
        let c = ModelContext(try exportContainer())
        let e = make(c)
        let id = e.syncId
        let d = RecentlyDeleted.move(e, in: c)
        #expect(try c.fetch(FetchDescriptor<Entry>()).isEmpty)
        #expect(try c.fetch(FetchDescriptor<PurgeRecord>()).isEmpty)
        #expect(d.entryId == id && d.preview == "[synthetic] A morning I want to keep.")
        #expect(RecentlyDeleted.daysLeft(d) == 30)
    }

    @Test func restoreBringsBackTheSameEntry() throws {
        let c = ModelContext(try exportContainer())
        let e = make(c)
        let id = e.syncId
        let d = RecentlyDeleted.move(e, in: c)
        let back = try #require(RecentlyDeleted.restore(d, in: c))
        #expect(back.syncId == id)
        #expect(back.text == "[synthetic] A morning I want to keep.\nSecond line.")
        #expect(back.photoData == Data([1, 2, 3]))
        #expect(back.releaseNote?.feelings == [.calm])
        #expect(try c.fetch(FetchDescriptor<DeletedEntry>()).isEmpty)
    }

    @Test func afterThirtyDaysItIsGoneForGoodWithATombstone() throws {
        let c = ModelContext(try exportContainer())
        let e = make(c)
        let id = e.syncId
        let now = Date()
        RecentlyDeleted.move(e, in: c, now: now)
        #expect(RecentlyDeleted.purgeExpired(in: c, now: now.addingTimeInterval(86400 * 29)) == 0)
        #expect(RecentlyDeleted.purgeExpired(in: c, now: now.addingTimeInterval(86400 * 31)) == 1)
        #expect(try c.fetch(FetchDescriptor<DeletedEntry>()).isEmpty)
        #expect(try c.fetch(FetchDescriptor<PurgeRecord>()).map(\.entryId) == [id])
    }
}
