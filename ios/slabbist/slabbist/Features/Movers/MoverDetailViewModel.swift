import Foundation
import Observation
import OSLog

/// View-model for the card-detail screen reached by tapping a mover
/// row. Holds the price-history fetch state for one (product_id,
/// sub_type) — the mover row itself supplies the static metadata
/// (name, current price, etc.), so this object only owns the chart
/// data.
@MainActor
@Observable
final class MoverDetailViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded([PriceHistoryDTO])
        case error(String)
    }

    let mover: MoverDTO
    var state: State = .idle

    private let repository: MoversRepository
    private let days: Int

    init(
        mover: MoverDTO,
        repository: MoversRepository = SupabaseMoversRepository(),
        days: Int = 90
    ) {
        self.mover = mover
        self.repository = repository
        self.days = days
    }

    /// Idempotent loader — first call hits the network, subsequent
    /// calls (e.g. NavigationStack push/pop revisits) return cached
    /// state immediately.
    func loadIfNeeded() async {
        switch state {
        case .loaded, .loading:
            return
        case .idle, .error:
            await fetch()
        }
    }

    func refresh() async {
        await fetch()
    }

    private func fetch() async {
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
}
