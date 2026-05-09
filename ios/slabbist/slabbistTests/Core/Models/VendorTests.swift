import Foundation
import SwiftData
import Testing
@testable import slabbist

@MainActor
struct VendorTests {
    @Test func insertAndFetchVendor() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let storeId = UUID()
        let vendor = Vendor(
            id: UUID(),
            storeId: storeId,
            displayName: "Acme Cards",
            contactMethod: "phone",
            contactValue: "555-0100",
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        context.insert(vendor)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Vendor>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.displayName == "Acme Cards")
        #expect(fetched.first?.archivedAt == nil)
    }
}
