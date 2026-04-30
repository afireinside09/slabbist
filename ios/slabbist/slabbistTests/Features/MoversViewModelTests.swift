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

    @Test("eBay tab auto-bootstraps to newest set and corrects empty tier")
    func ebayBootstrapAndTierAutoCorrect() async {
        let repo = StubMoversRepository(
            ebaySets: [
                MoversSetDTO(groupId: 100, groupName: "Newest with listings", moversCount: 4),
                MoversSetDTO(groupId: 99,  groupName: "Older with listings",  moversCount: 2),
            ],
            ebayTierCounts: [
                // The newest set has nothing in under_5 (default
                // priceTier on first eBay visit) — auto-correct
                // should move us to the lowest non-empty band.
                100: [.tier5_25: 4, .tier50_100: 1],
                99:  [.under5: 2],
            ]
        )
        let vm = MoversViewModel(repository: repo)
        vm.switchTab(to: .ebayListings)
        #expect(vm.setFilter == nil)
        #expect(vm.priceTier == .under5)

        // Pass 1: bootstrap setFilter
        await vm.loadIfNeeded()
        #expect(vm.setFilter == 100)

        // Pass 2: load tier counts; .under5 has 0 listings → auto-correct to .tier5_25
        await vm.loadIfNeeded()
        #expect(vm.priceTier == .tier5_25)

        // Pass 3: actually fetch listings for the corrected combo
        await vm.loadIfNeeded()
        #expect(repo.callCounts["ebay-listings-100-tier_5_25"] == 1)
        #expect(repo.callCounts["ebay-listings-100-under_5"] == nil,
                "should NEVER fetch for the empty (group, tier)")

        // Available tiers should hide bands with zero counts.
        #expect(vm.availableEbayTiers == [.tier5_25, .tier50_100])
    }

    @Test("switching tabs preserves each tab's previous filter state")
    func tabStateRoundTrips() async {
        let repo = StubMoversRepository(
            setsByLanguage: [
                3: [
                    MoversSetDTO(groupId: 1, groupName: "Set A", moversCount: 1),
                    MoversSetDTO(groupId: 2, groupName: "Set B", moversCount: 1),
                ],
                85: [MoversSetDTO(groupId: 9, groupName: "JP Set", moversCount: 1)],
            ],
            setMoversByGroupTier: [
                .init(groupId: 1, tier: "tier_5_25"):  [Self.row(id: 1, name: "A", pct: 5,  direction: "gainers")],
                .init(groupId: 2, tier: "tier_5_25"):  [Self.row(id: 2, name: "B", pct: 6,  direction: "gainers")],
                .init(groupId: 9, tier: "tier_25_50"): [Self.row(id: 9, name: "C", pct: 7,  direction: "gainers")],
            ]
        )
        let vm = MoversViewModel(repository: repo)
        // Land on English with a specific (set, tier).
        vm.priceTier = .tier5_25
        await vm.loadIfNeeded()
        await vm.loadIfNeeded()
        vm.setFilter = 2
        await vm.loadIfNeeded()
        #expect(vm.tab == .english)
        #expect(vm.setFilter == 2)
        #expect(vm.priceTier == .tier5_25)

        // Hop to eBay Listings — slot for English saved, eBay defaults applied.
        vm.switchTab(to: .ebayListings)
        #expect(vm.tab == .ebayListings)
        #expect(vm.setFilter == nil)
        #expect(vm.priceTier == .under5)

        // Browse on eBay tab.
        vm.priceTier = .tier200Plus
        vm.setFilter = nil

        // Hop back to English — saved (Set B, $5–$25) restored.
        vm.switchTab(to: .english)
        #expect(vm.tab == .english)
        #expect(vm.setFilter == 2)
        #expect(vm.priceTier == .tier5_25)

        // Hop back to eBay — saved (nil, $200+) restored.
        vm.switchTab(to: .ebayListings)
        #expect(vm.setFilter == nil)
        #expect(vm.priceTier == .tier200Plus)
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
    private let ebaySets: [MoversSetDTO]
    private let ebayTierCounts: [Int /* groupId */: [MoversPriceTier: Int]]
    private(set) var callCounts: [String: Int] = [:]

    init(
        setsByLanguage: [Int: [MoversSetDTO]] = [:],
        setMoversByGroupTier: [GroupTierKey: [MoverDTO]?] = [:],
        ebaySets: [MoversSetDTO] = [],
        ebayTierCounts: [Int: [MoversPriceTier: Int]] = [:]
    ) {
        self.setsByLanguage = setsByLanguage
        self.setMoversByGroupTier = setMoversByGroupTier
        self.ebaySets = ebaySets
        self.ebayTierCounts = ebayTierCounts
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

    func ebayListingsSets() async throws -> [MoversSetDTO] {
        callCounts["ebay-sets", default: 0] += 1
        return ebaySets
    }

    func ebayListingsBrowse(
        priceTier: MoversPriceTier?, groupId: Int?, limit: Int
    ) async throws -> [EbayListingBrowseRowDTO] {
        let key = "ebay-listings-\(groupId.map(String.init) ?? "any")-\(priceTier?.rawValue ?? "any")"
        callCounts[key, default: 0] += 1
        return []
    }

    func ebayListingsTierCounts(
        groupId: Int?
    ) async throws -> [MoversPriceTier: Int] {
        let key = "ebay-tier-counts-\(groupId.map(String.init) ?? "any")"
        callCounts[key, default: 0] += 1
        if let groupId, let counts = ebayTierCounts[groupId] {
            return counts
        }
        return [:]
    }
}
