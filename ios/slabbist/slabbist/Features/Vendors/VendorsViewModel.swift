import Foundation
import SwiftData

/// View model that hosts the active and archived vendor lists for the
/// current store. Mutations go through `VendorsRepository`, which writes
/// SwiftData and the outbox in one transaction; this type just refreshes
/// its published lists afterward so the views observe the change.
@MainActor
@Observable
final class VendorsViewModel {
    private let repo: VendorsRepository
    private(set) var active: [Vendor] = []
    private(set) var archived: [Vendor] = []

    init(repo: VendorsRepository) {
        self.repo = repo
    }

    /// Resolves the signed-in user's `Store` from the local model context
    /// and returns a configured view model. Returns `nil` when the user is
    /// signed out or their `Store` hasn't synced yet (fresh signup waiting
    /// on the outbox worker). The call site decides what to render while
    /// this is `nil`.
    static func resolve(context: ModelContext, kicker: OutboxKicker, session: SessionStore) -> VendorsViewModel? {
        guard let userId = session.userId else { return nil }
        let ownerId = userId
        var descriptor = FetchDescriptor<Store>(
            predicate: #Predicate<Store> { $0.ownerUserId == ownerId }
        )
        descriptor.fetchLimit = 1
        guard let store = try? context.fetch(descriptor).first else { return nil }
        let repo = VendorsRepository(context: context, kicker: kicker, currentStoreId: store.id)
        return VendorsViewModel(repo: repo)
    }

    /// Reload both lists from SwiftData. Cheap (in-memory after first
    /// fetch); call after every write or when the view appears.
    func refresh() {
        active = (try? repo.listActive()) ?? []
        archived = (try? repo.listArchived()) ?? []
    }

    @discardableResult
    func upsert(id: UUID?, displayName: String, contactMethod: String?, contactValue: String?, notes: String?) throws -> Vendor {
        let v = try repo.upsert(
            id: id,
            displayName: displayName,
            contactMethod: contactMethod,
            contactValue: contactValue,
            notes: notes
        )
        refresh()
        return v
    }

    func archive(_ vendor: Vendor) throws {
        try repo.archive(vendor)
        refresh()
    }

    func reactivate(_ vendor: Vendor) throws {
        try repo.reactivate(vendor)
        refresh()
    }
}
