import XCTest
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
}
