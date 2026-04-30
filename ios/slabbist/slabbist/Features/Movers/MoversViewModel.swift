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
    /// Selected set (group_id). `nil` only during the initial bootstrap
    /// before the sets list lands, or after a language switch when the
    /// new language hasn't been bootstrapped yet. The view-model
    /// auto-picks the newest available set the moment the sets list
    /// resolves — there is no "All sets" UX.
    var setFilter: Int?
    /// Default `.under5` because the product wants users to enter the
    /// tab on a concrete price band, not the noisy unfiltered view.
    var priceTier: MoversPriceTier = .under5
    var gainers: SectionState = .idle
    var losers: SectionState = .idle

    /// Sets list per language. Always fetched with the server's
    /// `'all'` tier so the rail shows every set that has any mover —
    /// keeps the user's pick visible even when they're filtering a
    /// sparse tier.
    var setsByLanguage: [MoversLanguage: [MoversSetDTO]] = [:]
    var setsLoadError: String?

    /// Timestamp of the latest successful fetch for the current
    /// (language, set, tier) — drives the "updated Nm ago" subtitle.
    var lastUpdatedAt: Date?

    private let repository: MoversRepository
    private let limit: Int

    /// Cache key for per-set + tier fetches. group_id alone would be
    /// unique across languages in TCGCSV, but keeping language in the
    /// key makes the cache self-explanatory and hardens us against
    /// any future cross-category id collision.
    private struct SetKey: Hashable {
        let language: MoversLanguage
        let groupId: Int
        let priceTier: MoversPriceTier
    }
    private var setCache: [SetKey: [MoverDTO]] = [:]

    /// Tracks the most recently requested filter so a late response
    /// from a stale (language, set, tier) doesn't overwrite current
    /// state when the user toggles quickly.
    private var inflightFingerprint: Fingerprint?
    private struct Fingerprint: Equatable {
        let language: MoversLanguage
        let groupId: Int
        let priceTier: MoversPriceTier
    }

    init(
        repository: MoversRepository = SupabaseMoversRepository(),
        limit: Int = 10
    ) {
        self.repository = repository
        self.limit = limit
    }

    /// Load both sections for the current (language, setFilter, tier).
    /// Two-phase:
    ///   1. Make sure the language's sets list is loaded.
    ///   2. If `setFilter` is nil (first load or post-language-switch),
    ///      auto-pick the newest set and return — mutating `setFilter`
    ///      retriggers the view's `.task(id:)`, which re-enters here
    ///      with the populated filter and falls through to phase 3.
    ///   3. Fetch the per-set movers (single round-trip; both
    ///      directions arrive together).
    func loadIfNeeded() async {
        await ensureSetsLoaded(force: false)

        if setFilter == nil {
            if let first = currentSets.first?.groupId {
                setFilter = first
                return
            }
            // No sets in this language at all — flip to an explicit
            // empty state so the section bodies render the empty
            // copy instead of the perpetual skeleton shimmer.
            gainers = .loaded([])
            losers  = .loaded([])
            return
        }

        if let groupId = setFilter {
            await fetchSetMovers(groupId: groupId, force: false)
        }
    }

    /// Pull-to-refresh: always hits the network for both the sets
    /// list (a new scrape may have introduced new sets) and the
    /// current set's movers.
    func refresh() async {
        await ensureSetsLoaded(force: true)
        if let groupId = setFilter {
            await fetchSetMovers(groupId: groupId, force: true)
        }
    }

    /// Convenience for the view: sets list for the current language.
    var currentSets: [MoversSetDTO] {
        setsByLanguage[language] ?? []
    }

    // MARK: - Mover fetch

    private func fetchSetMovers(groupId: Int, force: Bool) async {
        let lang = language
        let tier = priceTier
        let fp = Fingerprint(language: lang, groupId: groupId, priceTier: tier)
        inflightFingerprint = fp

        let key = SetKey(language: lang, groupId: groupId, priceTier: tier)
        if !force, let cached = setCache[key] {
            applySetRows(cached)
            return
        }

        gainers = .loading
        losers  = .loading

        let outcome = await fetchSetMoversOutcome(groupId: groupId, priceTier: tier)

        guard isCurrent(fp) else { return }

        switch outcome {
        case let .success(rows):
            setCache[key] = rows
            applySetRows(rows)
            stampUpdatedIfAnyLoaded()
        case let .failure(err):
            let msg = err.localizedDescription
            gainers = .error(msg)
            losers  = .error(msg)
        }

        if inflightFingerprint == fp { inflightFingerprint = nil }
    }

    private func applySetRows(_ rows: [MoverDTO]) {
        // Split a single payload into the two sections. Direction is
        // populated by the per-set RPC; if absent (older payload or
        // unexpected shape) we fall back to sign-of-pct_change so the
        // UI never silently drops rows.
        var g: [MoverDTO] = []
        var l: [MoverDTO] = []
        for row in rows {
            switch row.direction {
            case "gainers": g.append(row)
            case "losers":  l.append(row)
            default:        if row.pctChange >= 0 { g.append(row) } else { l.append(row) }
            }
        }
        gainers = .loaded(g)
        losers  = .loaded(l)
    }

    // MARK: - Sets list

    private func ensureSetsLoaded(force: Bool) async {
        let lang = language
        if !force, setsByLanguage[lang] != nil { return }

        do {
            // The sets-list RPC scans every tier server-side, so the
            // rail is a navigational constant — your selected set
            // stays visible even when the picked tier is sparse for
            // that set.
            let sets = try await repository.sets(language: lang)
            guard language == lang else { return }
            setsByLanguage[lang] = sets
            setsLoadError = nil
        } catch {
            AppLog.movers.error(
                "movers sets(\(lang.rawValue, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)"
            )
            setsLoadError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func fetchSetMoversOutcome(
        groupId: Int,
        priceTier: MoversPriceTier
    ) async -> Result<[MoverDTO], Error> {
        do {
            let rows = try await repository.setMovers(
                groupId: groupId,
                priceTier: priceTier
            )
            return .success(rows)
        } catch {
            AppLog.movers.error(
                "setMovers(\(groupId, privacy: .public),\(priceTier.rawValue, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)"
            )
            return .failure(error)
        }
    }

    private func isCurrent(_ fp: Fingerprint) -> Bool {
        language == fp.language && setFilter == fp.groupId && priceTier == fp.priceTier
    }

    private func stampUpdatedIfAnyLoaded() {
        if case .loaded = gainers { lastUpdatedAt = Date() }
        else if case .loaded = losers { lastUpdatedAt = Date() }
    }
}
