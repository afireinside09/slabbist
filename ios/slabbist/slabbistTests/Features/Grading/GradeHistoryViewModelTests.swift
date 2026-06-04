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

    // A successful load must reach `.loaded` so an empty result reads as a
    // real "no grades yet" empty state (and not a perpetual spinner).
    @Test("successful load marks loadState .loaded")
    func loadSuccessMarksLoaded() async {
        let repo = HistoryFakeRepo(rows: [.fixture(grade: 8)])
        let vm = GradeHistoryViewModel(repo: repo)
        await vm.load()
        #expect(vm.loadState == .loaded)
    }

    // The bug this guards: a fetch failure used to collapse to `rows = []`,
    // which the view rendered identically to "you have no grades yet." A
    // failed load must be distinguishable so the user sees "couldn't load",
    // not a false empty state.
    @Test("failed load surfaces .failed, not a false empty state")
    func failedLoadIsDistinct() async {
        let repo = HistoryFakeRepo(rows: [], failReads: true)
        let vm = GradeHistoryViewModel(repo: repo)
        await vm.load()
        #expect(vm.loadState == .failed)
    }

    // A failed star write must not silently mutate the local row as though
    // it synced — the UI would then lie about state the server never got.
    @Test("toggleStar failure surfaces an error and leaves the row unchanged")
    func toggleStarFailureDoesNotMutate() async {
        let row = GradeEstimateDTO.fixture(grade: 8, starred: false)
        let repo = HistoryFakeRepo(rows: [row])
        let vm = GradeHistoryViewModel(repo: repo)
        await vm.load()
        repo.failWrites = true
        await vm.toggleStar(id: row.id, starred: true)
        #expect(vm.actionError != nil)
        #expect(vm.rows.first?.isStarred == false)
    }

    // Symmetric to the star case: a failed delete must not remove the row,
    // or the list would drop a grade the server still has.
    @Test("delete failure surfaces an error and keeps the row")
    func deleteFailureKeepsRow() async {
        let row = GradeEstimateDTO.fixture(grade: 8)
        let repo = HistoryFakeRepo(rows: [row])
        let vm = GradeHistoryViewModel(repo: repo)
        await vm.load()
        repo.failWrites = true
        await vm.delete(id: row.id)
        #expect(vm.actionError != nil)
        #expect(vm.rows.count == 1)
    }
}

// Fake repo + DTO fixture helper. Matches the actor-isolation pattern from
// GradingCaptureViewModelTests: protocol is `nonisolated`, so the fake is
// not `@MainActor`; use `nonisolated(unsafe)` for mutable storage.
final class HistoryFakeRepo: GradeEstimateRepository {
    nonisolated(unsafe) var rows: [GradeEstimateDTO]
    nonisolated(unsafe) var failReads: Bool
    nonisolated(unsafe) var failWrites: Bool
    struct Boom: Error {}
    init(rows: [GradeEstimateDTO], failReads: Bool = false, failWrites: Bool = false) {
        self.rows = rows
        self.failReads = failReads
        self.failWrites = failWrites
    }

    func listForCurrentUser(page: Page, includeTotalCount: Bool) async throws -> PagedResult<GradeEstimateDTO> {
        if failReads { throw Boom() }
        return PagedResult(rows: rows, totalCount: rows.count, page: page)
    }
    func find(id: UUID) async throws -> GradeEstimateDTO? { rows.first { $0.id == id } }
    func setStarred(id: UUID, starred: Bool) async throws {
        if failWrites { throw Boom() }
        if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].isStarred = starred }
    }
    func delete(id: UUID) async throws {
        if failWrites { throw Boom() }
        rows.removeAll { $0.id == id }
    }
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
