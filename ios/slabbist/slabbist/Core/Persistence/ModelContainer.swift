import Foundation
import SwiftData

enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            Store.self,
            StoreMember.self,
            Lot.self,
            Scan.self,
            Vendor.self,
            OutboxItem.self,
            GradedCardIdentity.self,
            GradedMarketSnapshot.self,
            StoreTransaction.self,
            TransactionLine.self
            // Plan 2 adds: GradedCard
        ])
        let configurationName = "slabbist"
        let config = ModelConfiguration(configurationName, schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // GradedMarketSnapshot reshapes are mostly lightweight-migratable
            // when new attributes have default values (see `source` in the
            // model). When migration still fails — e.g. from a previous build
            // that landed before the default existed, leaving the store in a
            // half-migrated state — blow the store away and start fresh.
            // Comp data is recoverable from a cheap re-fetch, and all other
            // models cascade through Store/Lot ownership which is server-
            // backed via the outbox.
            //
            // The store file basename matches the ModelConfiguration name —
            // ModelConfiguration("slabbist", …) → slabbist.store. SQLite WAL
            // mode means the persistent store is actually three files; all
            // three must be removed together or the rebuild can re-hydrate
            // the schema mismatch from the WAL.
            let appSupport = URL.applicationSupportDirectory
            for suffix in [".store", ".store-shm", ".store-wal"] {
                let url = appSupport.appending(path: "\(configurationName)\(suffix)")
                try? FileManager.default.removeItem(at: url)
            }
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError(
                    "AppModelContainer: rebuild after migration failure also failed. " +
                    "Original error: \(error.localizedDescription)"
                )
            }
        }
    }()

    /// In-memory container for tests and previews.
    static func inMemory() -> ModelContainer {
        let schema = Schema([
            Store.self, StoreMember.self, Lot.self,
            Scan.self, Vendor.self, OutboxItem.self,
            GradedCardIdentity.self,
            GradedMarketSnapshot.self,
            StoreTransaction.self, TransactionLine.self
        ])
        let config = ModelConfiguration("slabbist-tests", schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
