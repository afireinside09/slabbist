import Foundation
import Testing
@testable import slabbist

@Suite("MoversViewModel")
@MainActor
struct MoversViewModelTests {
    @Test("first load picks the newest set and fetches its tier slate")
    func bootstrapsToNewestSet() async {
        let setRows = [
            Self.row(id: 11, name: "Charizard", pct: 18.2, direction: "gainers"),
            Self.row(id: 12, name: "Pikachu",   pct: -9.4, direction: "losers"),
        ]
        let repo = StubMoversRepository(
            setsByLanguage: [
                3: [
                    MoversSetDTO(groupId: 1, groupName: "Latest Set",  moversCount: 2),
                    MoversSetDTO(groupId: 2, groupName: "Older Set",   moversCount: 5),
                ]
            ],
            // Default tier is .under5 — fixture matches.
            setMoversByGroupTier: [.init(groupId: 1, tier: "under_5"): setRows]
        )
        let vm = MoversViewModel(repository: repo)

        // Bootstrap: phase 1 loads sets, phase 2 sets setFilter, returns.
        await vm.loadIfNeeded()
        // The view's .task(id:) re-fires when setFilter mutates; mirror
        // that here.
        await vm.loadIfNeeded()

        #expect(vm.setFilter == 1)
        #expect(vm.priceTier == .under5)
        #expect(vm.gainers.rows.map(\.productId) == [11])
        #expect(vm.losers.rows.map(\.productId)  == [12])
        #expect(repo.callCounts["sets-3"] == 1)
        #expect(repo.callCounts["set-1-under_5"] == 1)
    }

    @Test("switching tier preserves the selected set")
    func tierSwitchKeepsSet() async {
        let setRows = [
            Self.row(id: 11, name: "Cheap rocket", pct: 200, direction: "gainers"),
        ]
        let setRowsMid = [
            Self.row(id: 22, name: "Mid mover",    pct: 25,  direction: "gainers"),
        ]
        let repo = StubMoversRepository(
            setsByLanguage: [
                3: [MoversSetDTO(groupId: 1, groupName: "Perfect Order", moversCount: 1)]
            ],
            setMoversByGroupTier: [
                .init(groupId: 1, tier: "tier_5_25"):   setRows,
                .init(groupId: 1, tier: "tier_25_50"):  setRowsMid,
            ]
        )
        let vm = MoversViewModel(repository: repo)
        vm.priceTier = .tier5_25
        await vm.loadIfNeeded() // bootstrap to set 1
        await vm.loadIfNeeded() // fetch set 1 movers in tier 5-25

        #expect(vm.setFilter == 1)
        #expect(vm.gainers.rows.map(\.productId) == [11])

        // Tier change: setFilter must stay on 1.
        vm.priceTier = .tier25_50
        await vm.loadIfNeeded()

        #expect(vm.setFilter == 1, "tier switch must NOT reset the set filter")
        #expect(vm.gainers.rows.map(\.productId) == [22])
        #expect(repo.callCounts["set-1-tier_5_25"]  == 1)
        #expect(repo.callCounts["set-1-tier_25_50"] == 1)
    }

    @Test("switching set preserves the selected tier")
    func setSwitchKeepsTier() async {
        let repo = StubMoversRepository(
            setsByLanguage: [
                3: [
                    MoversSetDTO(groupId: 1, groupName: "Set A", moversCount: 1),
                    MoversSetDTO(groupId: 2, groupName: "Set B", moversCount: 1),
                ]
            ],
            setMoversByGroupTier: [
                .init(groupId: 1, tier: "tier_50_100"): [Self.row(id: 1, name: "A1", pct: 10, direction: "gainers")],
                .init(groupId: 2, tier: "tier_50_100"): [Self.row(id: 2, name: "B1", pct: 12, direction: "gainers")],
            ]
        )
        let vm = MoversViewModel(repository: repo)
        vm.priceTier = .tier50_100
        await vm.loadIfNeeded() // bootstrap → setFilter = 1
        await vm.loadIfNeeded()

        vm.setFilter = 2
        await vm.loadIfNeeded()

        #expect(vm.priceTier == .tier50_100, "set switch must NOT reset the tier filter")
        #expect(vm.gainers.rows.map(\.productId) == [2])
    }

    @Test("language switch clears setFilter and re-bootstraps")
    func languageSwitchRebootstraps() async {
        let repo = StubMoversRepository(
            setsByLanguage: [
                3:  [MoversSetDTO(groupId: 1, groupName: "EN Set", moversCount: 1)],
                85: [MoversSetDTO(groupId: 9, groupName: "JP Set", moversCount: 1)],
            ],
            setMoversByGroupTier: [
                .init(groupId: 1, tier: "under_5"): [Self.row(id: 1, name: "EN", pct: 5, direction: "gainers")],
                .init(groupId: 9, tier: "under_5"): [Self.row(id: 9, name: "JP", pct: 7, direction: "gainers")],
            ]
        )
        let vm = MoversViewModel(repository: repo)
        await vm.loadIfNeeded()
        await vm.loadIfNeeded()
        #expect(vm.setFilter == 1)

        // The view's language setter nils setFilter; mirror that here.
        vm.language = .japanese
        vm.setFilter = nil
        await vm.loadIfNeeded()
        await vm.loadIfNeeded()

        #expect(vm.setFilter == 9, "expected JP newest set after language switch")
        #expect(vm.gainers.rows.map(\.productId) == [9])
    }

    @Test("per-set + tier results are cached")
    func cachesPerSetTier() async {
        let repo = StubMoversRepository(
            setsByLanguage: [
                3: [MoversSetDTO(groupId: 1, groupName: "Set A", moversCount: 1)]
            ],
            setMoversByGroupTier: [
                .init(groupId: 1, tier: "under_5"): [Self.row(id: 1, name: "A", pct: 1, direction: "gainers")]
            ]
        )
        let vm = MoversViewModel(repository: repo)
        await vm.loadIfNeeded()
        await vm.loadIfNeeded()

        // Re-enter the same combo: should not refetch.
        await vm.loadIfNeeded()

        #expect(repo.callCounts["set-1-under_5"] == 1)
    }

    @Test("refresh bypasses the cache")
    func refreshBypassesCache() async {
        let repo = StubMoversRepository(
            setsByLanguage: [
                3: [MoversSetDTO(groupId: 1, groupName: "Set A", moversCount: 1)]
            ],
            setMoversByGroupTier: [
                .init(groupId: 1, tier: "under_5"): [Self.row(id: 1, name: "A", pct: 1, direction: "gainers")]
            ]
        )
        let vm = MoversViewModel(repository: repo)
        await vm.loadIfNeeded()
        await vm.loadIfNeeded()

        await vm.refresh()

        #expect(repo.callCounts["set-1-under_5"] == 2)
        #expect(repo.callCounts["sets-3"] == 2)
    }

    @Test("no sets in language → both sections fall to empty (not skeleton)")
    func emptyLanguageSurfacesEmptyState() async {
        let repo = StubMoversRepository(setsByLanguage: [3: []])
        let vm = MoversViewModel(repository: repo)
        await vm.loadIfNeeded()

        #expect(vm.setFilter == nil)
        if case .loaded(let rows) = vm.gainers { #expect(rows.isEmpty) }
        else { Issue.record("gainers should be .loaded([]), got \(vm.gainers)") }
    }

    // MARK: - Helpers

    static func row(id: Int, name: String, pct: Double, direction: String) -> MoverDTO {
        MoverDTO(
            productId: id,
            productName: name,
            groupName: "Some Set",
            imageUrl: nil,
            subTypeName: "Normal",
            currentPrice: 100.0 * (1 + pct / 100),
            previousPrice: 100.0,
            absChange: 100.0 * (pct / 100),
            pctChange: pct,
            capturedAt: Date(),
            previousCapturedAt: Date(timeIntervalSinceNow: -86_400),
            direction: direction
        )
    }
}

// MARK: - Stub repository

/// Deterministic in-memory repository. Sets are keyed by language
/// only (matching the production behavior — sets list is tier-
/// independent). Per-set movers are keyed by (groupId, tier) so
/// tests can vary fixtures across tiers.
final class StubMoversRepository: MoversRepository, @unchecked Sendable {
    struct StubError: Error {}
    struct GroupTierKey: Hashable { let groupId: Int; let tier: String }

    private let setsByLanguage: [Int: [MoversSetDTO]]
    private let setMoversByGroupTier: [GroupTierKey: [MoverDTO]?]
    private(set) var callCounts: [String: Int] = [:]

    init(
        setsByLanguage: [Int: [MoversSetDTO]] = [:],
        setMoversByGroupTier: [GroupTierKey: [MoverDTO]?] = [:]
    ) {
        self.setsByLanguage = setsByLanguage
        self.setMoversByGroupTier = setMoversByGroupTier
    }

    func topMovers(
        language: MoversLanguage,
        direction: MoversDirection,
        limit: Int,
        priceTier: MoversPriceTier
    ) async throws -> [MoverDTO] {
        // Production view-model no longer calls topMovers; tests
        // shouldn't exercise it either.
        Issue.record("topMovers should not be called in the per-set flow")
        return []
    }

    func sets(
        language: MoversLanguage
    ) async throws -> [MoversSetDTO] {
        let key = "sets-\(language.rawValue)"
        callCounts[key, default: 0] += 1
        return setsByLanguage[language.rawValue] ?? []
    }

    func setMovers(
        groupId: Int,
        priceTier: MoversPriceTier
    ) async throws -> [MoverDTO] {
        let key = "set-\(groupId)-\(priceTier.rawValue)"
        callCounts[key, default: 0] += 1
        let lookup = GroupTierKey(groupId: groupId, tier: priceTier.rawValue)
        guard let payload = setMoversByGroupTier[lookup] else {
            // No fixture for this combination — model "no movers in
            // this tier for this set" by returning an empty array,
            // which is what the server does.
            return []
        }
        guard let rows = payload else { throw StubError() }
        return rows
    }

    func priceHistory(
        productId: Int, subType: String, days: Int
    ) async throws -> [PriceHistoryDTO] {
        // Movers list flow doesn't fetch history — exercising it
        // here would be a regression.
        Issue.record("priceHistory should not be called from list flow")
        return []
    }

    func ebayListings(
        productId: Int, subType: String, limit: Int
    ) async throws -> [MoverEbayListingDTO] {
        Issue.record("ebayListings should not be called from list flow")
        return []
    }
}
