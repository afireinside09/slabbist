import Foundation
import SwiftData
import Testing
@testable import slabbist

@MainActor
struct LotOfferStateTests {
    @Test func defaultsToDrafting() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let lot = Lot(
            id: UUID(),
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "Test",
            createdAt: Date(),
            updatedAt: Date()
        )
        context.insert(lot)
        try context.save()
        #expect(lot.lotOfferState == LotOfferState.drafting.rawValue)
        #expect(lot.marginPctSnapshot == nil)
    }

    @Test func enumCasesMatchSpec() {
        let cases = LotOfferState.allCases.map(\.rawValue).sorted()
        #expect(cases == ["accepted", "declined", "drafting", "paid", "presented", "priced", "voided"])
    }
}
