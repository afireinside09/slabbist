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

    /// Loading-state envelope for the eBay browse-list section.
    enum EbayBrowseState: Equatable {
        case idle
        case loading
        case loaded([EbayListingBrowseRowDTO])
        case error(String)
    }

    /// Loading-state envelope for the eBay-mode set-rail RPC.
    enum EbaySetsState: Equatable {
        case idle
        case loading
        case loaded([MoversSetDTO])
        case error(String)
    }

    /// Loading-state envelope for the per-set tier counts RPC. Drives
    /// the eBay-tab tier-rail filtering — only tiers with > 0
    /// listings are shown.
    enum EbayTierCountsState: Equatable {
        case idle
        case loading
        case loaded([MoversPriceTier: Int])
        case error(String)
    }

    // MARK: - Picker state

    /// Top-level tab. Drives data fetching and set-rail source.
    var tab: MoversTab = .english

    // MARK: - Movers-mode state (English / Japanese)

    /// The active language while a movers tab is selected. Stays in
    /// sync with `tab` for `.english` / `.japanese`. When the user
    /// is on `.ebayListings`, this is whatever it was last — the
    /// movers fetch path doesn't run, so the value is dormant.
    var language: MoversLanguage = .english
    /// Selected set (group_id). `nil` only during the initial bootstrap
    /// before the sets list lands, or after a language switch when the
    /// new language hasn't been bootstrapped yet.
    var setFilter: Int?
    var priceTier: MoversPriceTier = .under5
    var gainers: SectionState = .idle
    var losers: SectionState = .idle

    /// Sets list per language for movers mode. Tier-independent.
    var setsByLanguage: [MoversLanguage: [MoversSetDTO]] = [:]
    var setsLoadError: String?

    /// Timestamp of the latest successful fetch for the current
    /// (tab, set, tier) combo.
    var lastUpdatedAt: Date?

    // MARK: - eBay browse state

    /// Set rail source while `tab == .ebayListings`. Different RPC
    /// than the movers set rail because we want only sets that have
    /// at least one matched listing.
    var ebaySetsState: EbaySetsState = .idle
    /// Browse-list payload while `tab == .ebayListings`.
    var ebayListingsState: EbayBrowseState = .idle
    /// Per-tier counts for the currently-selected eBay set. Drives
    /// the tier rail's filtering — only positive-count tiers render.
    var ebayTierCountsState: EbayTierCountsState = .idle

    /// Tiers with at least one listing for the current selection.
    /// Falls back to all picker options when counts haven't loaded
    /// yet, so the rail isn't visibly empty during the brief load
    /// window.
    var availableEbayTiers: [MoversPriceTier] {
        if case let .loaded(counts) = ebayTierCountsState {
            let nonzero = MoversPriceTier.pickerOptions.filter { (counts[$0] ?? 0) > 0 }
            return nonzero.isEmpty ? MoversPriceTier.pickerOptions : nonzero
        }
        return MoversPriceTier.pickerOptions
    }

    // MARK: - Per-tab snapshots

    /// Each tab keeps its own (setFilter, priceTier) so switching
    /// tabs doesn't lose the user's place. The active tab's values
    /// live in `setFilter` / `priceTier` directly; inactive tabs'
    /// values land here on switch and are restored when the user
    /// comes back.
    private struct TabSlot {
        var setFilter: Int?
        var priceTier: MoversPriceTier
    }
    private var savedSlots: [MoversTab: TabSlot] = [:]

    // MARK: - Caches + concurrency

    private let repository: MoversRepository
    private let limit: Int

    /// Movers-mode per-set cache. group_id alone would be unique
    /// across languages in TCGCSV but keeping language in the key
    /// makes the cache self-explanatory.
    private struct SetKey: Hashable {
        let language: MoversLanguage
        let groupId: Int
        let priceTier: MoversPriceTier
    }
    private var setCache: [SetKey: [MoverDTO]] = [:]

    /// Tracks the most recently requested filter so a late response
    /// from a stale (language, set, tier) doesn't overwrite current
    /// state when the user toggles quickly.
    private var inflightFingerprint: MoversFingerprint?
    private struct MoversFingerprint: Equatable {
        let language: MoversLanguage
        let groupId: Int
        let priceTier: MoversPriceTier
    }

    /// eBay-browse cache. Keyed on (tier, groupId) so the user can
    /// flip tiers/sets and not re-fetch when revisiting.
    private struct EbayBrowseKey: Hashable {
        let priceTier: MoversPriceTier
        let groupId: Int?
    }
    private var ebayBrowseCache: [EbayBrowseKey: [EbayListingBrowseRowDTO]] = [:]
    private var ebayInflight: EbayBrowseKey?

    /// Tier-count cache. Keyed by groupId; the global "no group"
    /// case is keyed under -1 since `Int?` isn't directly hashable
    /// as a dict key in older Swift versions and this is simpler.
    private var ebayTierCountsCache: [Int: [MoversPriceTier: Int]] = [:]

    init(
        repository: MoversRepository = SupabaseMoversRepository(),
        limit: Int = 10
    ) {
        self.repository = repository
        self.limit = limit
    }

    // MARK: - Tab switching

    /// Switch to a new tab, snapshotting the outgoing tab's filter
    /// state and restoring the incoming tab's previously-saved slot
    /// if any. First-time visits to a tab use the per-tab default
    /// (no set filter for eBay browse, nil-bootstrap for movers).
    func switchTab(to next: MoversTab) {
        guard next != tab else { return }
        savedSlots[tab] = TabSlot(setFilter: setFilter, priceTier: priceTier)
        tab = next
        if let lang = next.moversLanguage {
            language = lang
        }
        if let restored = savedSlots[next] {
            setFilter = restored.setFilter
            priceTier = restored.priceTier
        } else {
            // First-time defaults per tab.
            setFilter = nil
            priceTier = .under5
        }
    }

    // MARK: - Load orchestration

    /// Single entry point used by the view's `.task(id:)`. Branches
    /// to the movers- or eBay-mode load path based on the current tab.
    func loadIfNeeded() async {
        switch tab {
        case .english, .japanese:
            await loadMoversIfNeeded()
        case .ebayListings:
            await loadEbayIfNeeded()
        }
    }

    func refresh() async {
        switch tab {
        case .english, .japanese:
            await refreshMovers()
        case .ebayListings:
            await ensureEbaySetsLoaded(force: true)
            if let groupId = setFilter {
                await ensureEbayTierCountsLoaded(groupId: groupId, force: true)
            }
            await fetchEbayBrowse(force: true)
        }
    }

    /// Set rail source for the current tab. The view binds to this
    /// directly so flipping tabs swaps the rail's contents.
    var currentSets: [MoversSetDTO] {
        switch tab {
        case .english, .japanese:
            return setsByLanguage[language] ?? []
        case .ebayListings:
            if case let .loaded(sets) = ebaySetsState { return sets }
            return []
        }
    }

    // MARK: - Movers mode

    private func loadMoversIfNeeded() async {
        await ensureSetsLoaded(force: false)

        if setFilter == nil {
            if let first = currentSets.first?.groupId {
                setFilter = first
                return
            }
            // No sets in this language at all — flip to an explicit
            // empty state.
            gainers = .loaded([])
            losers  = .loaded([])
            return
        }

        if let groupId = setFilter {
            await fetchSetMovers(groupId: groupId, force: false)
        }
    }

    private func refreshMovers() async {
        await ensureSetsLoaded(force: true)
        if let groupId = setFilter {
            await fetchSetMovers(groupId: groupId, force: true)
        }
    }

    private func fetchSetMovers(groupId: Int, force: Bool) async {
        let lang = language
        let tier = priceTier
        let fp = MoversFingerprint(language: lang, groupId: groupId, priceTier: tier)
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

    private func ensureSetsLoaded(force: Bool) async {
        let lang = language
        if !force, setsByLanguage[lang] != nil { return }

        do {
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

    private func isCurrent(_ fp: MoversFingerprint) -> Bool {
        tab.isMovers
            && language == fp.language
            && setFilter == fp.groupId
            && priceTier == fp.priceTier
    }

    // MARK: - eBay browse mode

    private func loadEbayIfNeeded() async {
        // Step 1 — sets list. Drives both the rail and the bootstrap
        // pick below.
        await ensureEbaySetsLoaded(force: false)

        // Step 2 — bootstrap setFilter to the newest set with
        // listings if the user hasn't picked one yet. The mutation
        // retriggers the view's `.task(id:)`; we return early so the
        // restart picks up the populated filter.
        if setFilter == nil {
            if case let .loaded(sets) = ebaySetsState, let first = sets.first?.groupId {
                setFilter = first
                return
            }
            // No sets with any listings — surface an explicit empty
            // state instead of a perpetual skeleton.
            ebayListingsState = .loaded([])
            return
        }

        // Step 3 — tier counts for the currently-selected set. Lets
        // the rail hide tiers that have zero listings AND lets us
        // auto-correct an out-of-range priceTier.
        guard let groupId = setFilter else { return }
        await ensureEbayTierCountsLoaded(groupId: groupId, force: false)

        // Step 4 — auto-correct priceTier if the saved/default tier
        // has zero listings for this set. Same retrigger pattern as
        // the bootstrap above: mutate state, return, let the .task
        // re-run with corrected filters.
        if let corrected = autoCorrectedTier(), corrected != priceTier {
            priceTier = corrected
            return
        }

        // Step 5 — listings for (set, tier).
        await fetchEbayBrowse(force: false)
    }

    /// If the current priceTier has zero listings for the active
    /// set, return the lowest-priced tier that does. Otherwise nil
    /// (current is fine, no correction needed).
    private func autoCorrectedTier() -> MoversPriceTier? {
        guard case let .loaded(counts) = ebayTierCountsState else { return nil }
        if (counts[priceTier] ?? 0) > 0 { return nil }
        return MoversPriceTier.pickerOptions.first { (counts[$0] ?? 0) > 0 }
    }

    private func ensureEbaySetsLoaded(force: Bool) async {
        if !force, case .loaded = ebaySetsState { return }
        ebaySetsState = .loading
        do {
            let sets = try await repository.ebayListingsSets()
            ebaySetsState = .loaded(sets)
        } catch {
            AppLog.movers.error(
                "ebayListingsSets failed: \(error.localizedDescription, privacy: .public)"
            )
            ebaySetsState = .error(error.localizedDescription)
        }
    }

    private func ensureEbayTierCountsLoaded(groupId: Int, force: Bool) async {
        if !force, let cached = ebayTierCountsCache[groupId] {
            ebayTierCountsState = .loaded(cached)
            return
        }
        ebayTierCountsState = .loading
        do {
            let counts = try await repository.ebayListingsTierCounts(groupId: groupId)
            // Bail if the user moved on while we were in flight; we
            // don't want stale counts to clobber the new state.
            guard tab == .ebayListings, setFilter == groupId else { return }
            ebayTierCountsCache[groupId] = counts
            ebayTierCountsState = .loaded(counts)
        } catch {
            guard tab == .ebayListings, setFilter == groupId else { return }
            AppLog.movers.error(
                "ebayListingsTierCounts(\(groupId, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)"
            )
            ebayTierCountsState = .error(error.localizedDescription)
        }
    }

    private func fetchEbayBrowse(force: Bool) async {
        let key = EbayBrowseKey(priceTier: priceTier, groupId: setFilter)
        ebayInflight = key

        if !force, let cached = ebayBrowseCache[key] {
            ebayListingsState = .loaded(cached)
            return
        }

        ebayListingsState = .loading

        do {
            let rows = try await repository.ebayListingsBrowse(
                priceTier: priceTier,
                groupId: setFilter,
                limit: 60
            )
            // Late-response guard — if the user changed filters
            // while we were in flight, drop the result silently.
            guard tab == .ebayListings, ebayInflight == key else { return }
            ebayBrowseCache[key] = rows
            ebayListingsState = .loaded(rows)
            stampUpdatedIfAnyLoaded()
        } catch {
            guard tab == .ebayListings, ebayInflight == key else { return }
            AppLog.movers.error(
                "ebayListingsBrowse failed: \(error.localizedDescription, privacy: .public)"
            )
            ebayListingsState = .error(error.localizedDescription)
        }

        if ebayInflight == key { ebayInflight = nil }
    }

    // MARK: - Misc

    private func stampUpdatedIfAnyLoaded() {
        switch tab {
        case .english, .japanese:
            if case .loaded = gainers { lastUpdatedAt = Date() }
            else if case .loaded = losers { lastUpdatedAt = Date() }
        case .ebayListings:
            if case .loaded = ebayListingsState { lastUpdatedAt = Date() }
        }
    }
}
