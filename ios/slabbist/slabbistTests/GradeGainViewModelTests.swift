import XCTest
import SwiftData
@testable import slabbist

@MainActor
final class GradeGainViewModelTests: XCTestCase {

    private func row(_ id: Int, raw: Int, psa10: Int) -> GradeGainDTO {
        GradeGainDTO(productId: id, productName: "C\(id)", groupName: "S", imageUrl: nil,
                     subTypeName: "Holofoil", rawPriceCents: raw, psa10PriceCents: psa10,
                     spreadCents: psa10 - raw, ptTrend: nil, ptConfidence: nil, ptSaleCount: nil)
    }

    struct FakeRepo: GradeGainRepository {
        let sets_: [GradeGainSetDTO]
        let gains_: [GradeGainDTO]
        func sets() async throws -> [GradeGainSetDTO] { sets_ }
        func setGains(groupId: Int, priceTier: MoversPriceTier) async throws -> [GradeGainDTO] { gains_ }
    }

    struct FailingRepo: GradeGainRepository {
        struct Boom: Error {}
        func sets() async throws -> [GradeGainSetDTO] { throw Boom() }
        func setGains(groupId: Int, priceTier: MoversPriceTier) async throws -> [GradeGainDTO] { throw Boom() }
    }

    private func inMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: GradeGainSnapshot.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func test_fee_hides_rows_that_go_unprofitable() async {
        // Card with $30 spread survives a $25 fee; $10-spread card does not.
        let repo = FakeRepo(
            sets_: [GradeGainSetDTO(groupId: 1, groupName: "S", gainsCount: 2, publishedOn: nil)],
            gains_: [row(1, raw: 500, psa10: 3500), row(2, raw: 500, psa10: 1500)] // spreads 3000, 1000
        )
        let vm = GradeGainViewModel(repository: repo)
        await vm.load()
        vm.feeCents = 2500
        let visible = vm.visibleRows
        XCTAssertEqual(visible.map(\.productId), [1], "only the >$25-spread card stays profitable after the fee")
        XCTAssertEqual(visible.first?.profitCents(feeCents: vm.feeCents), 500)
    }

    func test_bootstraps_to_newest_set_when_none_selected() async {
        let repo = FakeRepo(
            sets_: [
                GradeGainSetDTO(groupId: 10, groupName: "Older", gainsCount: 1, publishedOn: Date(timeIntervalSince1970: 0)),
                GradeGainSetDTO(groupId: 20, groupName: "Newer", gainsCount: 1, publishedOn: Date(timeIntervalSince1970: 10_000)),
            ],
            gains_: [row(1, raw: 100, psa10: 5000)]
        )
        let vm = GradeGainViewModel(repository: repo)
        await vm.load()
        XCTAssertEqual(vm.selectedSet, 20, "newest set (by published_on, server-ordered first) is selected")
    }

    // A successful load persists the result; a later load whose fetch fails
    // (offline) must fall back to those cached rows, labeled stale — not go
    // blank. This is the whole point of the last-known-good cache.
    func test_offline_restores_cached_rows_labeled_stale() async throws {
        let context = try inMemoryContext()
        let okRepo = FakeRepo(
            sets_: [GradeGainSetDTO(groupId: 1, groupName: "Base", gainsCount: 1, publishedOn: nil)],
            gains_: [row(1, raw: 500, psa10: 3500)]
        )
        let warm = GradeGainViewModel(repository: okRepo)
        warm.attach(context)
        await warm.load()
        XCTAssertFalse(warm.isStale)
        XCTAssertEqual(warm.visibleRows.map(\.productId), [1])

        // A fresh VM sharing the same store, whose fetch now fails.
        let offline = GradeGainViewModel(repository: FailingRepo())
        offline.attach(context)
        await offline.load()
        XCTAssertTrue(offline.isStale, "offline fetch should fall back to the cache")
        XCTAssertEqual(offline.visibleRows.map(\.productId), [1], "shows the cached rows")
        XCTAssertNotNil(offline.staleFetchedAt)
    }

    // Offline with nothing cached must surface the error, not a false empty.
    func test_offline_with_no_cache_surfaces_error() async throws {
        let vm = GradeGainViewModel(repository: FailingRepo())
        vm.attach(try inMemoryContext())
        await vm.load()
        XCTAssertFalse(vm.isStale)
        guard case .error = vm.section else {
            return XCTFail("expected .error when offline with no cached snapshot")
        }
    }
}
