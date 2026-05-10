import Foundation
import SwiftData
import Testing
@testable import slabbist

@Suite("VendorsRepository")
@MainActor
struct VendorsRepositoryTests {
    /// No-op kicker — tests don't exercise the drainer hop.
    private static func noopKicker() -> OutboxKicker {
        OutboxKicker { }
    }

    private func makeRepo() -> (VendorsRepository, ModelContext, UUID) {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let storeId = UUID()
        let repo = VendorsRepository(context: context, kicker: Self.noopKicker(), currentStoreId: storeId)
        return (repo, context, storeId)
    }

    @Test("upsert with nil id creates the vendor and enqueues an upsertVendor outbox item")
    func upsertCreatesVendorAndOutboxItem() throws {
        let (repo, context, _) = makeRepo()
        let vendor = try repo.upsert(
            id: nil,
            displayName: "Acme",
            contactMethod: "phone",
            contactValue: "555-0100",
            notes: nil
        )
        #expect(vendor.displayName == "Acme")
        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        #expect(outbox.contains(where: { $0.kind == .upsertVendor }))
    }

    @Test("upsert by existing id mutates in place — never duplicates")
    func upsertUpdatesExistingByIdAndDoesNotDuplicate() throws {
        let (repo, context, _) = makeRepo()
        let v1 = try repo.upsert(id: nil, displayName: "Acme", contactMethod: nil, contactValue: nil, notes: nil)
        _ = try repo.upsert(id: v1.id, displayName: "Acme Cards LLC", contactMethod: "email", contactValue: "x@y", notes: nil)
        let vendors = try context.fetch(FetchDescriptor<Vendor>())
        #expect(vendors.count == 1)
        #expect(vendors.first?.displayName == "Acme Cards LLC")
        #expect(vendors.first?.contactMethod == "email")
    }

    @Test("archive stamps archivedAt and enqueues an archiveVendor outbox item")
    func archiveSetsArchivedAtAndEnqueuesItem() throws {
        let (repo, context, _) = makeRepo()
        let v = try repo.upsert(id: nil, displayName: "Acme", contactMethod: nil, contactValue: nil, notes: nil)
        try repo.archive(v)
        #expect(v.archivedAt != nil)
        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        #expect(outbox.contains(where: { $0.kind == .archiveVendor }))
    }

    @Test("listActive excludes archived vendors")
    func listActiveExcludesArchived() throws {
        let (repo, _, _) = makeRepo()
        let active = try repo.upsert(id: nil, displayName: "Active", contactMethod: nil, contactValue: nil, notes: nil)
        let archived = try repo.upsert(id: nil, displayName: "Archived", contactMethod: nil, contactValue: nil, notes: nil)
        try repo.archive(archived)
        let listed = try repo.listActive()
        #expect(listed.contains(where: { $0.id == active.id }))
        #expect(!listed.contains(where: { $0.id == archived.id }))
    }

    @Test("listActive sorts by displayName ascending")
    func listActiveSortsByDisplayNameAscending() throws {
        let (repo, _, _) = makeRepo()
        _ = try repo.upsert(id: nil, displayName: "Zeta", contactMethod: nil, contactValue: nil, notes: nil)
        _ = try repo.upsert(id: nil, displayName: "Alpha", contactMethod: nil, contactValue: nil, notes: nil)
        let listed = try repo.listActive()
        #expect(listed.first?.displayName == "Alpha")
    }
}
