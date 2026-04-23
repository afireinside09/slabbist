import Foundation
import Testing
@testable import slabbist

@Suite("GradeHistoryViewModel")
@MainActor
struct GradeHistoryViewModelTests {
    @Test("loads first page on .load()")
    func loads() async throws {
        let repo = HistoryFakeRepo(rows: [.fixture(grade: 8), .fixture(grade: 9)])
        let vm = GradeHistoryViewModel(repo: repo)
        await vm.load()
        #expect(vm.rows.count == 2)
    }

    @Test("filter starred narrows the list")
    func filterStarred() async throws {
        let repo = HistoryFakeRepo(rows: [
            .fixture(grade: 8, starred: false),
            .fixture(grade: 9, starred: true),
        ])
        let vm = GradeHistoryViewModel(repo: repo)
        await vm.load()
        vm.filter = .starred
        #expect(vm.visibleRows.count == 1)
        #expect(vm.visibleRows.first?.compositeGrade == 9)
    }

    @Test("toggleStar updates row in place")
    func toggleStar() async throws {
        let row = GradeEstimateDTO.fixture(grade: 8, starred: false)
        let repo = HistoryFakeRepo(rows: [row])
        let vm = GradeHistoryViewModel(repo: repo)
        await vm.load()
        await vm.toggleStar(id: row.id, starred: true)
        #expect(vm.rows.first?.isStarred == true)
    }

    @Test("delete removes row from local state")
    func delete() async throws {
        let row = GradeEstimateDTO.fixture(grade: 8)
        let repo = HistoryFakeRepo(rows: [row])
        let vm = GradeHistoryViewModel(repo: repo)
        await vm.load()
        await vm.delete(id: row.id)
        #expect(vm.rows.isEmpty)
    }
}

// Fake repo + DTO fixture helper. Matches the actor-isolation pattern from
// GradingCaptureViewModelTests: protocol is `nonisolated`, so the fake is
// not `@MainActor`; use `nonisolated(unsafe)` for mutable storage.
final class HistoryFakeRepo: GradeEstimateRepository {
    nonisolated(unsafe) var rows: [GradeEstimateDTO]
    init(rows: [GradeEstimateDTO]) { self.rows = rows }

    func listForCurrentUser(page: Page, includeTotalCount: Bool) async throws -> PagedResult<GradeEstimateDTO> {
        PagedResult(rows: rows, totalCount: rows.count, page: page)
    }
    func find(id: UUID) async throws -> GradeEstimateDTO? { rows.first { $0.id == id } }
    func setStarred(id: UUID, starred: Bool) async throws {
        if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].isStarred = starred }
    }
    func delete(id: UUID) async throws { rows.removeAll { $0.id == id } }
    func requestEstimate(
        frontPath: String, backPath: String,
        centeringFront: CenteringRatios, centeringBack: CenteringRatios,
        includeOtherGraders: Bool
    ) async throws -> GradeEstimateDTO { fatalError("unused") }
}

extension GradeEstimateDTO {
    static func fixture(grade: Double, starred: Bool = false) -> GradeEstimateDTO {
        GradeEstimateDTO(
            id: UUID(), userId: UUID(), scanId: nil,
            frontImagePath: "", backImagePath: "",
            frontThumbPath: "", backThumbPath: "",
            imagesPurgedAt: nil,
            centeringFront: CenteringRatios(left: 0.5, right: 0.5, top: 0.5, bottom: 0.5),
            centeringBack:  CenteringRatios(left: 0.5, right: 0.5, top: 0.5, bottom: 0.5),
            subGrades: SubGrades(centering: grade, corners: grade, edges: grade, surface: grade),
            subGradeNotes: SubGradeNotes(centering: "", corners: "", edges: "", surface: ""),
            compositeGrade: grade, confidence: "high", verdict: "submit_value", verdictReasoning: "",
            otherGraders: nil, modelVersion: "v1", isStarred: starred, createdAt: Date()
        )
    }
}
