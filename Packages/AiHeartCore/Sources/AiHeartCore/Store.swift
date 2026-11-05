import Foundation
import SwiftData

public enum AiHeartStore {
    /// Local store with complete file protection, excluded from device backups (docs/02).
    /// Sync (CloudKit private database) is off until the iCloud capability is set up (M16, docs/09 #7).
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(AiHeartSchema.models)
        if inMemory {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        }
        let dir = try storeDirectory()
        let config = ModelConfiguration(schema: schema, url: dir.appendingPathComponent("AiHeart.store"), cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: config)
    }

    static func storeDirectory() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var dir = base.appendingPathComponent("AiHeart", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        #if os(iOS) || os(watchOS)
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: dir.path)
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try dir.setResourceValues(values)
        return dir
    }

    /// Settings is a single row; enforce that in code.
    @MainActor
    public static func settings(in context: ModelContext) -> AppSettings {
        if let existing = try? context.fetch(FetchDescriptor<AppSettings>(sortBy: [SortDescriptor(\.updatedAt)])).first {
            return existing
        }
        let s = AppSettings()
        context.insert(s)
        try? context.save()
        return s
    }
}
