import AiHeartCore
import Foundation
import SwiftData
import UIKit

/// Imports her private About me seed once (CLAUDE.md, "The private seed"). The file is
/// copied into the app's Documents folder from her Mac; it is read here, stored in the
/// encrypted About me row, and deleted. It is never logged or printed.
@MainActor
enum SeedImport {
    static let fileName = "about-me.private.md"
    /// A memory seed adds to About me and never replaces what she wrote. Same care: read, stored, deleted.
    static let memorySeedName = "memory-seed.md"

    /// Entries recovered on her Mac (for example after a lost save) and copied back into Documents.
    static let restoreEntriesName = "restore-entries.json"

    static func runIfPresent(_ context: ModelContext) {
        importAboutMe(context)
        importMemorySeed(context)
        importRestoredEntries(context)
    }

    private struct RestoredEntry: Decodable {
        var createdAt: Date
        var text: String
        var word: String?
    }

    /// Adds each entry back as kept, with its original time. Skips one that is already there
    /// (same time and text), so running twice adds nothing. Read, stored, file deleted; never logged.
    private static func importRestoredEntries(_ context: ModelContext) {
        let url = URL.documentsDirectory.appendingPathComponent(restoreEntriesName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url), let items = try? decoder.decode([RestoredEntry].self, from: data) else {
            NSLog("AiHeartImport restore: unreadable file")
            return
        }
        let existing = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        var added = 0
        for item in items {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  !existing.contains(where: { abs($0.createdAt.timeIntervalSince(item.createdAt)) < 1 && $0.text == text }) else { continue }
            let e = Entry(kind: .write, createdAt: item.createdAt)
            e.text = text
            e.word = item.word
            e.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
            context.insert(e)
            added += 1
        }
        try? context.save()
        NSLog("AiHeartImport restore: added %d of %d", added, items.count)
    }

    private static func importMemorySeed(_ context: ModelContext) {
        let url = URL.documentsDirectory.appendingPathComponent(memorySeedName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let rows = (try? context.fetch(FetchDescriptor<AboutMe>(sortBy: [SortDescriptor(\.updatedAt)]))) ?? []
        let row = rows.first ?? { let r = AboutMe(); context.insert(r); return r }()
        row.markdown = AboutMeDoc.parse(row.markdown).mergingMemorySeed(text).markdown
        row.updatedAt = .now
        try? context.save()
    }

    /// Her context for a model prompt, from About me. Empty when there is none.
    static func promptContext(_ context: ModelContext, full: Bool) -> String {
        let rows = (try? context.fetch(FetchDescriptor<AboutMe>(sortBy: [SortDescriptor(\.updatedAt)]))) ?? []
        guard let row = rows.first else { return "" }
        return AboutMeDoc.parse(row.markdown).promptContext(full: full)
    }

    private static func importAboutMe(_ context: ModelContext) {
        let url = URL.documentsDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let rows = (try? context.fetch(FetchDescriptor<AboutMe>(sortBy: [SortDescriptor(\.updatedAt)]))) ?? []
        let row = rows.first ?? { let r = AboutMe(); context.insert(r); return r }()
        rows.dropFirst().forEach(context.delete)
        row.markdown = AboutMeDoc.parse(text).markdown
        row.updatedAt = .now
        try? context.save()
    }
}
