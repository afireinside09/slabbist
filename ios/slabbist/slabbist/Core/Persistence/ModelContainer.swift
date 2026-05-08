import Foundation
import SwiftData

enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            Store.self,
            StoreMember.self,
            Lot.self,
            Scan.self,
            OutboxItem.self,
            GradedCardIdentity.self,
            GradedMarketSnapshot.self
            // Plan 2 adds: GradedCard
        ])
        let config = ModelConfiguration("slabbist", schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // GradedMarketSnapshot reshapes are not lightweight-migratable:
            // first PriceCharting moved to a per-tier ladder, then PPT
            // added pptTCGPlayerId/pptURL, and now poketrace introduces
            // `source` plus a parallel pt_* column family. On first launch
            // after each shape change, blow the store away and start fresh —
            // comp data is recoverable from a cheap re-fetch, all other
            // models cascade through Store/Lot ownership which is
            // server-backed.
            try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "default.store"))
            return try! ModelContainer(for: schema, configurations: [config])
        }
    }()

    /// In-memory container for tests and previews.
    static func inMemory() -> ModelContainer {
        let schema = Schema([
            Store.self, StoreMember.self, Lot.self,
            Scan.self, OutboxItem.self,
            GradedCardIdentity.self,
            GradedMarketSnapshot.self
        ])
        let config = ModelConfiguration("slabbist-tests", schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
