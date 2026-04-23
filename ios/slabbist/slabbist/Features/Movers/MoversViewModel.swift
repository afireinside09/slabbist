import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class MoversViewModel {
    /// Per-section state — gainers and losers load in parallel and can
    /// resolve independently (e.g. gainers succeed while losers fail).
    enum SectionState: Equatable {
        case idle
        case loading
        case loaded([MoverDTO])
        case error(String)

        var rows: [MoverDTO] {
            if case let .loaded(rows) = self { return rows }
            return []
        }

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    var language: MoversLanguage = .english
    var gainers: SectionState = .idle
    var losers: SectionState = .idle

    /// Timestamp of the latest successful fetch for the current
    /// language — drives the "updated Nm ago" subtitle.
    var lastUpdatedAt: Date?

    private let repository: MoversRepository
    private let limit: Int
    private let subType: String

    private struct CacheKey: Hashable {
        let language: MoversLanguage
        let direction: MoversDirection
    }
    private var cache: [CacheKey: [MoverDTO]] = [:]
    /// Tracks the most recently requested language so a late
    /// response from a stale language doesn't overwrite current state.
    private var inflightLanguage: MoversLanguage?

    init(
        repository: MoversRepository = SupabaseMoversRepository(),
        limit: Int = 10,
        subType: String = "Normal"
    ) {
        self.repository = repository
        self.limit = limit
        self.subType = subType
    }

    /// Load both sections for the current language. Serves cached
    /// results instantly if both are already in memory; otherwise
    /// issues two parallel RPCs.
    func loadIfNeeded() async {
        await fetch(for: language, force: false)
    }

    /// Pull-to-refresh: always hits the network and re-populates
    /// both sections.
    func refresh() async {
        await fetch(for: language, force: true)
    }

    private func fetch(for lang: MoversLanguage, force: Bool) async {
        let gainerKey = CacheKey(language: lang, direction: .gainers)
        let loserKey  = CacheKey(language: lang, direction: .losers)

        if !force, let g = cache[gainerKey], let l = cache[loserKey] {
            gainers = .loaded(g)
            losers  = .loaded(l)
            return
        }

        inflightLanguage = lang

        if force || cache[gainerKey] == nil { gainers = .loading }
        if force || cache[loserKey]  == nil { losers  = .loading }

        async let gOutcome = fetchOne(language: lang, direction: .gainers)
        async let lOutcome = fetchOne(language: lang, direction: .losers)
        let (g, l) = await (gOutcome, lOutcome)

        guard language == lang, inflightLanguage == lang else { return }

        switch g {
        case let .success(rows):
            cache[gainerKey] = rows
            gainers = .loaded(rows)
        case let .failure(err):
            gainers = .error(err.localizedDescription)
        }

        switch l {
        case let .success(rows):
            cache[loserKey] = rows
            losers = .loaded(rows)
        case let .failure(err):
            losers = .error(err.localizedDescription)
        }

        // Stamp the timestamp only if at least one section resolved
        // successfully — a total failure shouldn't claim freshness.
        if case .loaded = gainers { lastUpdatedAt = Date() }
        else if case .loaded = losers { lastUpdatedAt = Date() }

        inflightLanguage = nil
    }

    private func fetchOne(
        language: MoversLanguage,
        direction: MoversDirection
    ) async -> Result<[MoverDTO], Error> {
        do {
            let rows = try await repository.topMovers(
                language: language,
                direction: direction,
                limit: limit,
                subType: subType
            )
            return .success(rows)
        } catch {
            AppLog.movers.error(
                "topMovers(\(direction.rawValue, privacy: .public), \(language.rawValue, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)"
            )
            return .failure(error)
        }
    }
}
