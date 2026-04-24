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
            GradedMarketSnapshot.self,
            SoldListingMirror.self
            // Plan 2 adds: GradedCard
        ])
        let config = ModelConfiguration("slabbist", schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    /// In-memory container for tests and previews.
    static func inMemory() -> ModelContainer {
        let schema = Schema([
            Store.self, StoreMember.self, Lot.self,
            Scan.self, OutboxItem.self,
            GradedCardIdentity.self,
            GradedMarketSnapshot.self,
            SoldListingMirror.self
        ])
        let config = ModelConfiguration("slabbist-tests", schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
