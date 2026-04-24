import Foundation
import Testing
import SwiftData
@testable import slabbist

@Suite("StoreHydrator")
@MainActor
struct StoreHydratorTests {
    @Test("hydrate inserts a new local Store when none exists")
    func insertsNewStore() async throws {
        let container = AppModelContainer.inMemory()
        let userId = UUID()
        let remote = StoreDTO(
            id: UUID(),
            name: "Downtown Cards",
            ownerUserId: userId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let repo = StubStoreRepository(listResult: .success([remote]))
        let hydrator = StoreHydrator(container: container, repository: repo)

        await hydrator.hydrateIfNeeded(userId: userId)

        #expect(hydrator.state == .ready(hydratedUserId: userId))
        let rows = try container.mainContext.fetch(FetchDescriptor<Store>())
        #expect(rows.count == 1)
        #expect(rows[0].id == remote.id)
        #expect(rows[0].name == "Downtown Cards")
        #expect(rows[0].ownerUserId == userId)
    }

    @Test("hydrate updates an existing local Store instead of duplicating")
    func updatesExistingStore() async throws {
        let container = AppModelContainer.inMemory()
        let userId = UUID()
        let storeId = UUID()
        // Seed an out-of-date local row.
        let stale = Store(
            id: storeId,
            name: "Old name",
            ownerUserId: userId,
            createdAt: Date(timeIntervalSince1970: 1_000_000_000)
        )
        container.mainContext.insert(stale)
        try container.mainContext.save()

        let fresh = StoreDTO(
            id: storeId,
            name: "New name",
            ownerUserId: userId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let repo = StubStoreRepository(listResult: .success([fresh]))
        let hydrator = StoreHydrator(container: container, repository: repo)

        await hydrator.hydrateIfNeeded(userId: userId)

        let rows = try container.mainContext.fetch(FetchDescriptor<Store>())
        #expect(rows.count == 1)
        #expect(rows[0].id == storeId)
        #expect(rows[0].name == "New name")
    }

    @Test("hydrateIfNeeded short-circuits on second call for same user")
    func idempotentForSameUser() async throws {
        let container = AppModelContainer.inMemory()
        let userId = UUID()
        let remote = StoreDTO(id: UUID(), name: "Store", ownerUserId: userId, createdAt: Date())
        let repo = StubStoreRepository(listResult: .success([remote]))
        let hydrator = StoreHydrator(container: container, repository: repo)

        await hydrator.hydrateIfNeeded(userId: userId)
        await hydrator.hydrateIfNeeded(userId: userId)

        #expect(repo.callCount == 1)
    }

    @Test("failure surfaces via state.failed and leaves the local store empty")
    func surfacesFailure() async throws {
        let container = AppModelContainer.inMemory()
        let userId = UUID()
        let repo = StubStoreRepository(listResult: .failure(StubError.network))
        let hydrator = StoreHydrator(container: container, repository: repo)

        await hydrator.hydrateIfNeeded(userId: userId)

        if case .failed(let message) = hydrator.state {
            #expect(message.isEmpty == false)
        } else {
            Issue.record("expected .failed state, got \(hydrator.state)")
        }
        let rows = try container.mainContext.fetch(FetchDescriptor<Store>())
        #expect(rows.isEmpty)
    }

    @Test("reset() clears hydrated state so a subsequent hydrate re-fetches")
    func resetForcesRefetch() async throws {
        let container = AppModelContainer.inMemory()
        let userId = UUID()
        let repo = StubStoreRepository(listResult: .success([
            StoreDTO(id: UUID(), name: "S", ownerUserId: userId, createdAt: Date())
        ]))
        let hydrator = StoreHydrator(container: container, repository: repo)

        await hydrator.hydrateIfNeeded(userId: userId)
        hydrator.reset()
        await hydrator.hydrateIfNeeded(userId: userId)

        #expect(repo.callCount == 2)
    }
}

// MARK: - Test doubles

private enum StubError: Error { case network }

private final class StubStoreRepository: StoreRepository, @unchecked Sendable {
    let listResult: Result<[StoreDTO], Error>
    private(set) var callCount = 0

    init(listResult: Result<[StoreDTO], Error>) {
        self.listResult = listResult
    }

    func listForCurrentUser(page: Page) async throws -> [StoreDTO] {
        callCount += 1
        return try listResult.get()
    }

    func find(id: UUID) async throws -> StoreDTO? { nil }
    func listOwnedBy(userId: UUID, page: Page) async throws -> [StoreDTO] { [] }
    func upsert(_ store: StoreDTO) async throws {}
    @discardableResult
    func upsertAndReturn(_ store: StoreDTO) async throws -> StoreDTO { store }
}
