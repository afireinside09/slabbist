import Foundation
import Testing
@testable import slabbist

@Suite("MoversViewModel")
@MainActor
struct MoversViewModelTests {
    @Test("loadIfNeeded populates gainers and losers in parallel")
    func loadsBothSections() async {
        let repo = StubMoversRepository(
            gainers: [Self.sample(id: 1, name: "Charizard", pct: 18.2)],
            losers:  [Self.sample(id: 2, name: "Pikachu",   pct: -12.4)]
        )
        let vm = MoversViewModel(repository: repo)

        await vm.loadIfNeeded()

        #expect(vm.gainers.rows.map(\.productName) == ["Charizard"])
        #expect(vm.losers.rows.map(\.productName)  == ["Pikachu"])
        #expect(vm.lastUpdatedAt != nil)
        #expect(repo.callCounts == ["gainers-3": 1, "losers-3": 1])
    }

    @Test("switching language triggers a second fetch and caches per-language")
    func cachesPerLanguage() async {
        let repo = StubMoversRepository(
            gainers: [Self.sample(id: 1, name: "A", pct: 5)],
            losers:  [Self.sample(id: 2, name: "B", pct: -5)]
        )
        let vm = MoversViewModel(repository: repo)

        await vm.loadIfNeeded()
        vm.language = .japanese
        await vm.loadIfNeeded()
        // Back to English — should come from cache.
        vm.language = .english
        await vm.loadIfNeeded()

        #expect(repo.callCounts["gainers-3"] == 1)
        #expect(repo.callCounts["losers-3"]  == 1)
        #expect(repo.callCounts["gainers-85"] == 1)
        #expect(repo.callCounts["losers-85"]  == 1)
    }

    @Test("refresh bypasses the cache")
    func refreshBypassesCache() async {
        let repo = StubMoversRepository(
            gainers: [Self.sample(id: 1, name: "A", pct: 1)],
            losers:  []
        )
        let vm = MoversViewModel(repository: repo)
        await vm.loadIfNeeded()
        await vm.refresh()

        #expect(repo.callCounts["gainers-3"] == 2)
        #expect(repo.callCounts["losers-3"]  == 2)
    }

    @Test("per-section failures don't clobber the sibling section")
    func partialFailureIsolated() async {
        let repo = StubMoversRepository(
            gainers: [Self.sample(id: 1, name: "OK", pct: 3)],
            losers:  nil // simulate an error path
        )
        let vm = MoversViewModel(repository: repo)
        await vm.loadIfNeeded()

        #expect(vm.gainers.rows.map(\.productName) == ["OK"])
        if case .error = vm.losers {
            // expected
        } else {
            Issue.record("losers section should be in error state, got \(vm.losers)")
        }
    }

    // MARK: - Helpers

    static func sample(id: Int, name: String, pct: Double) -> MoverDTO {
        MoverDTO(
            productId: id,
            productName: name,
            groupName: "Base Set",
            imageUrl: nil,
            subTypeName: "Normal",
            currentPrice: 100.0 * (1 + pct / 100),
            previousPrice: 100.0,
            absChange: 100.0 * (pct / 100),
            pctChange: pct,
            capturedAt: Date(),
            previousCapturedAt: Date(timeIntervalSinceNow: -86_400)
        )
    }
}

// MARK: - Stub repository

/// Deterministic in-memory repository. Pass `nil` for a direction to
/// have that call throw, exercising the view model's per-section
/// failure path without reaching the network.
final class StubMoversRepository: MoversRepository, @unchecked Sendable {
    struct StubError: Error {}

    private let gainers: [MoverDTO]?
    private let losers: [MoverDTO]?
    private(set) var callCounts: [String: Int] = [:]

    init(gainers: [MoverDTO]?, losers: [MoverDTO]?) {
        self.gainers = gainers
        self.losers  = losers
    }

    func topMovers(
        language: MoversLanguage,
        direction: MoversDirection,
        limit: Int,
        subType: String
    ) async throws -> [MoverDTO] {
        let key = "\(direction.rawValue)-\(language.rawValue)"
        callCounts[key, default: 0] += 1
        switch direction {
        case .gainers:
            guard let rows = gainers else { throw StubError() }
            return rows
        case .losers:
            guard let rows = losers else { throw StubError() }
            return rows
        }
    }
}
