import Foundation
import Observation

@MainActor
@Observable
final class GradeHistoryViewModel {
    enum Filter: Equatable { case all, starred }

    private(set) var rows: [GradeEstimateDTO] = []
    var filter: Filter = .all

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
        do {
            let result = try await repo.listForCurrentUser(page: .default, includeTotalCount: false)
            rows = result.rows
        } catch {
            rows = []
        }
    }

    func toggleStar(id: UUID, starred: Bool) async {
        try? await repo.setStarred(id: id, starred: starred)
        if let i = rows.firstIndex(where: { $0.id == id }) {
            rows[i].isStarred = starred
        }
    }

    func delete(id: UUID) async {
        try? await repo.delete(id: id)
        rows.removeAll { $0.id == id }
    }
}
