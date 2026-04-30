import Foundation
import Testing
@testable import slabbist

@Suite("MoverDetailViewModel")
@MainActor
struct MoverDetailViewModelTests {
    @Test("loadIfNeeded fetches the price history and lands in .loaded")
    func loadsHistory() async {
        let history = [
            PriceHistoryDTO(capturedAt: Date(timeIntervalSince1970: 1_700_000_000), marketPrice: 4.20),
            PriceHistoryDTO(capturedAt: Date(timeIntervalSince1970: 1_700_500_000), marketPrice: 5.00),
            PriceHistoryDTO(capturedAt: Date(timeIntervalSince1970: 1_701_000_000), marketPrice: 6.77),
        ]
        let repo = StubDetailRepo(history: history)
        let vm = MoverDetailViewModel(mover: Self.mover(), repository: repo)

        await vm.loadIfNeeded()

        if case let .loaded(rows) = vm.state {
            #expect(rows.map(\.marketPrice) == [4.20, 5.00, 6.77])
        } else {
            Issue.record("expected .loaded, got \(vm.state)")
        }
        #expect(repo.callCount == 1)
    }

    @Test("repeated loadIfNeeded calls hit the cache (idempotent)")
    func idempotentLoad() async {
        let repo = StubDetailRepo(history: [
            PriceHistoryDTO(capturedAt: Date(), marketPrice: 1)
        ])
        let vm = MoverDetailViewModel(mover: Self.mover(), repository: repo)

        await vm.loadIfNeeded()
        await vm.loadIfNeeded()
        await vm.loadIfNeeded()

        #expect(repo.callCount == 1)
    }

    @Test("refresh always re-fetches")
    func refreshAlwaysFetches() async {
        let repo = StubDetailRepo(history: [
            PriceHistoryDTO(capturedAt: Date(), marketPrice: 1)
        ])
        let vm = MoverDetailViewModel(mover: Self.mover(), repository: repo)

        await vm.loadIfNeeded()
        await vm.refresh()
        await vm.refresh()

        #expect(repo.callCount == 3)
    }

    @Test("repository error lands in .error")
    func errorPropagates() async {
        let repo = StubDetailRepo(history: nil)
        let vm = MoverDetailViewModel(mover: Self.mover(), repository: repo)

        await vm.loadIfNeeded()

        if case .error = vm.state {
            // expected
        } else {
            Issue.record("expected .error, got \(vm.state)")
        }
    }

    @Test("empty history lands in .loaded([])")
    func emptyHistoryIsLoaded() async {
        let repo = StubDetailRepo(history: [])
        let vm = MoverDetailViewModel(mover: Self.mover(), repository: repo)

        await vm.loadIfNeeded()

        if case .loaded(let rows) = vm.state {
            #expect(rows.isEmpty)
        } else {
            Issue.record("expected .loaded([]), got \(vm.state)")
        }
    }

    @Test("listings load in parallel with price history")
    func listingsLoadAlongsideHistory() async {
        let listings = [
            MoverEbayListingDTO(
                ebayItemId: "111",
                title: "PSA 10 Charizard 4/102 Holo",
                price: 2400,
                currency: "USD",
                url: "https://example.com/111",
                imageUrl: nil,
                gradingService: "PSA",
                grade: "10"
            )
        ]
        let repo = StubDetailRepo(history: [], listings: listings)
        let vm = MoverDetailViewModel(mover: Self.mover(), repository: repo)

        await vm.loadIfNeeded()

        if case .loaded(let rows) = vm.listingsState {
            #expect(rows.map(\.ebayItemId) == ["111"])
        } else {
            Issue.record("expected listings .loaded, got \(vm.listingsState)")
        }
        #expect(repo.callCount == 1)
        #expect(repo.listingsCallCount == 1)
    }

    @Test("a listings error doesn't taint the chart state")
    func listingsErrorIsolated() async {
        let repo = StubDetailRepo(
            history: [PriceHistoryDTO(capturedAt: Date(), marketPrice: 5)],
            listings: nil
        )
        let vm = MoverDetailViewModel(mover: Self.mover(), repository: repo)

        await vm.loadIfNeeded()

        if case .loaded = vm.state {
            // chart loaded
        } else {
            Issue.record("chart should be .loaded, got \(vm.state)")
        }
        if case .error = vm.listingsState {
            // expected
        } else {
            Issue.record("expected listings .error, got \(vm.listingsState)")
        }
    }

    // MARK: - Helpers

    static func mover() -> MoverDTO {
        MoverDTO(
            productId: 272708,
            productName: "Registeel",
            groupName: "SWSH10: Astral Radiance",
            imageUrl: "https://tcgplayer-cdn.tcgplayer.com/product/272708_200w.jpg",
            subTypeName: "Normal",
            currentPrice: 6.77,
            previousPrice: 0.17,
            absChange: 6.60,
            pctChange: 3882.35,
            capturedAt: Date(),
            previousCapturedAt: Date(timeIntervalSinceNow: -86_400 * 90)
        )
    }
}

/// Repository stub for the detail flow. Both `priceHistory` and
/// `ebayListings` are exercised; pass `nil` to either to simulate an
/// error path. The other movers methods are unreachable from the
/// detail screen and route through `Issue.record`.
final class StubDetailRepo: MoversRepository, @unchecked Sendable {
    struct StubError: Error {}

    private let history: [PriceHistoryDTO]?
    private let listings: [MoverEbayListingDTO]?
    private(set) var callCount: Int = 0
    private(set) var listingsCallCount: Int = 0

    init(
        history: [PriceHistoryDTO]?,
        listings: [MoverEbayListingDTO]? = []
    ) {
        self.history = history
        self.listings = listings
    }

    func topMovers(
        language: MoversLanguage, direction: MoversDirection,
        limit: Int, priceTier: MoversPriceTier
    ) async throws -> [MoverDTO] {
        Issue.record("topMovers should not be called from detail flow")
        return []
    }

    func sets(
        language: MoversLanguage
    ) async throws -> [MoversSetDTO] {
        Issue.record("sets should not be called from detail flow")
        return []
    }

    func setMovers(
        groupId: Int, priceTier: MoversPriceTier
    ) async throws -> [MoverDTO] {
        Issue.record("setMovers should not be called from detail flow")
        return []
    }

    func priceHistory(
        productId: Int, subType: String, days: Int
    ) async throws -> [PriceHistoryDTO] {
        callCount += 1
        guard let rows = history else { throw StubError() }
        return rows
    }

    func ebayListings(
        productId: Int, subType: String, limit: Int
    ) async throws -> [MoverEbayListingDTO] {
        listingsCallCount += 1
        guard let rows = listings else { throw StubError() }
        return rows
    }
}
