import Foundation
import SwiftData
import Testing
@testable import slabbist

@MainActor
struct ScanBuyPriceTests {
    @Test func vendorAskCentsRoundTrips() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let scan = Scan(
            id: UUID(), storeId: UUID(), lotId: UUID(), userId: UUID(),
            grader: .PSA, certNumber: "123",
            createdAt: Date(), updatedAt: Date()
        )
        scan.vendorAskCents = 1234     // renamed from offerCents
        scan.buyPriceCents = 800
        scan.buyPriceOverridden = true
        context.insert(scan)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Scan>())
        #expect(fetched.first?.vendorAskCents == 1234)
        #expect(fetched.first?.buyPriceCents == 800)
        #expect(fetched.first?.buyPriceOverridden == true)
    }
}
