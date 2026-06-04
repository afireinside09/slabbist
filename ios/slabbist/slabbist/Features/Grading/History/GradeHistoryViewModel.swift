import Foundation
import Observation

@MainActor
@Observable
final class GradeHistoryViewModel {
    enum Filter: Equatable { case all, starred }

    /// Load lifecycle for the list. `.loaded` with empty `rows` is a real
    /// "no grades yet" empty state; `.failed` means the fetch errored and
    /// must NOT look like an empty state — the old code collapsed both into
    /// `rows = []`, so a network failure told the user "pre-grade a slab"
    /// when the truth was "we couldn't load your grades."
    enum LoadState: Equatable { case loading, loaded, failed }

    private(set) var rows: [GradeEstimateDTO] = []
    private(set) var loadState: LoadState = .loading
    var filter: Filter = .all

    /// Transient error surfaced when a star/delete write fails, so the UI
    /// can alert instead of silently mutating the row as if it had synced.
    var actionError: String?

    private let repo: any GradeEstimateRepository

    init(repo: any GradeEstimateRepository) {
        self.repo = repo
    }

    var visibleRows: [GradeEstimateDTO] {
        switch filter {
        case .all:     return rows
        case .starred: return rows.filter(\.isStarred)
        }
    }

    func load() async {
        loadState = .loading
        do {
            let result = try await repo.listForCurrentUser(page: .default, includeTotalCount: false)
            rows = result.rows
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }

    func toggleStar(id: UUID, starred: Bool) async {
        do {
            try await repo.setStarred(id: id, starred: starred)
            if let i = rows.firstIndex(where: { $0.id == id }) {
                rows[i].isStarred = starred
            }
        } catch {
            actionError = "Couldn't update the star. Check your connection and try again."
        }
    }

    func delete(id: UUID) async {
        do {
            try await repo.delete(id: id)
            rows.removeAll { $0.id == id }
        } catch {
            actionError = "Couldn't delete that grade. Check your connection and try again."
        }
    }
}
