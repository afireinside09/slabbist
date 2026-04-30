import Foundation
import Observation
import OSLog

/// View-model for the card-detail screen reached by tapping a mover
/// row. Holds two independent fetch surfaces:
///   - `state`: 90-day price history powering the chart.
///   - `listingsState`: active eBay listings powering the carousel.
/// They run in parallel on first load and either can be refreshed
/// independently.
@MainActor
@Observable
final class MoverDetailViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded([PriceHistoryDTO])
        case error(String)
    }

    enum ListingsState: Equatable {
        case idle
        case loading
        case loaded([MoverEbayListingDTO])
        case error(String)
    }

    let mover: MoverDTO
    var state: State = .idle
    var listingsState: ListingsState = .idle

    private let repository: MoversRepository
    private let days: Int
    private let listingsLimit: Int

    init(
        mover: MoverDTO,
        repository: MoversRepository = SupabaseMoversRepository(),
        days: Int = 90,
        listingsLimit: Int = 24
    ) {
        self.mover = mover
        self.repository = repository
        self.days = days
        self.listingsLimit = listingsLimit
    }

    /// Idempotent loader — first call hits both endpoints in parallel,
    /// subsequent calls return cached state immediately. The two
    /// surfaces are independent so a failed listings fetch doesn't
    /// taint the chart.
    func loadIfNeeded() async {
        async let history: Void = loadHistoryIfNeeded()
        async let listings: Void = loadListingsIfNeeded()
        _ = await (history, listings)
    }

    func refresh() async {
        async let history: Void = fetchHistory()
        async let listings: Void = fetchListings()
        _ = await (history, listings)
    }

    private func loadHistoryIfNeeded() async {
        switch state {
        case .loaded, .loading:
            return
        case .idle, .error:
            await fetchHistory()
        }
    }

    private func loadListingsIfNeeded() async {
        switch listingsState {
        case .loaded, .loading:
            return
        case .idle, .error:
            await fetchListings()
        }
    }

    private func fetchHistory() async {
        state = .loading
        do {
            let rows = try await repository.priceHistory(
                productId: mover.productId,
                subType: mover.subTypeName,
                days: days
            )
            state = .loaded(rows)
        } catch {
            AppLog.movers.error(
                "priceHistory(\(self.mover.productId, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)"
            )
            state = .error(error.localizedDescription)
        }
    }

    private func fetchListings() async {
        listingsState = .loading
        do {
            let rows = try await repository.ebayListings(
                productId: mover.productId,
                subType: mover.subTypeName,
                limit: listingsLimit
            )
            listingsState = .loaded(rows)
        } catch {
            AppLog.movers.error(
                "ebayListings(\(self.mover.productId, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)"
            )
            listingsState = .error(error.localizedDescription)
        }
    }
}
