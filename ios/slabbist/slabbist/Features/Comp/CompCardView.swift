import SwiftUI
import SwiftData

/// Two-source comp card. The hero number is the *reconciled* headline
/// (server-computed average of PPT + Poketrace when both succeed,
/// single-source otherwise) sourced off `Scan.reconciledHeadlinePriceCents`.
///
/// Below the hero, a "Sources" strip shows each provider's number side
/// by side so the operator can sanity-check the reconciliation. The
/// PPT-shaped grade ladder, sparkline, caveat, and "View on Pokemon
/// Price Tracker" footer all continue to read from the PPT snapshot —
/// Poketrace contributes its own row on the sources strip and an
/// alternate sparkline series via the segmented toggle.
struct CompCardView: View {
    let scan: Scan
    let pptSnapshot: GradedMarketSnapshot?
    let poketraceSnapshot: GradedMarketSnapshot?

    /// Which provider feeds the inline sparkline. Defaults to PPT;
    /// switches to Poketrace only when the operator taps the segment.
    @State private var sparklineSource: SparklineSource = .ppt

    /// Cached sorted history per provider. The repository/snapshot
    /// pipeline doesn't guarantee chronological order, so we sort once
    /// per snapshot identity rather than on every body re-eval. Keyed on
    /// `(persistentModelID, fetchedAt)` so a refetch (delete+insert) and
    /// any in-place `fetchedAt` mutation both invalidate the cache.
    @State private var pptSortedHistory: [PriceHistoryPoint] = []
    @State private var poketraceSortedHistory: [PriceHistoryPoint] = []

    var body: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: 0) {
                heroRow
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, Spacing.l)
                    .padding(.bottom, Spacing.md)
                SlabCardDivider()
                sourcesRow
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.md)
                if showsSourceToggle {
                    SlabCardDivider()
                    sourceTogglePicker
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                if !activeSparklinePoints.isEmpty {
                    SlabCardDivider()
                    CompSparklineView(points: activeSparklinePoints)
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                if !ladderTiers.isEmpty {
                    SlabCardDivider()
                    ladderRail
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                if let caveat = caveatMessage {
                    SlabCardDivider()
                    caveatRow(caveat)
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                SlabCardDivider()
                footerRow
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.md)
            }
        }
        .onAppear {
            refreshSortedHistories()
            reconcileActiveSource()
        }
        .onChange(of: pptSnapshot == nil) { _, _ in reconcileActiveSource() }
        .onChange(of: poketraceSnapshot == nil) { _, _ in reconcileActiveSource() }
        // Recompute the sorted-history caches when the snapshot identity
        // changes (refetch produces a new SwiftData row → new
        // `persistentModelID`). `fetchedAt` is folded in so an in-place
        // refresh that mutates the existing row also invalidates.
        .onChange(of: pptSnapshotCacheKey) { _, _ in refreshSortedHistories() }
        .onChange(of: poketraceSnapshotCacheKey) { _, _ in refreshSortedHistories() }
    }

    /// Stable cache key for the PPT snapshot. `nil` collapses to an
    /// empty string so the `Equatable` change-detection inside
    /// `.onChange` still fires when the snapshot appears/disappears.
    private var pptSnapshotCacheKey: String {
        guard let s = pptSnapshot else { return "" }
        return "\(s.persistentModelID.hashValue)|\(s.fetchedAt.timeIntervalSince1970)"
    }

    private var poketraceSnapshotCacheKey: String {
        guard let s = poketraceSnapshot else { return "" }
        return "\(s.persistentModelID.hashValue)|\(s.fetchedAt.timeIntervalSince1970)"
    }

    private func refreshSortedHistories() {
        pptSortedHistory = (pptSnapshot?.priceHistory ?? []).sorted { $0.ts < $1.ts }
        poketraceSortedHistory = (poketraceSnapshot?.priceHistory ?? []).sorted { $0.ts < $1.ts }
    }

    // MARK: - Hero (reconciled, with adjacency-grade fallback)
    //
    // i18n deferred — Slabbist is US-only buy-side today, so we hardcode
    // `Locale(identifier: "en_US")` and English strings here. The
    // `Text(verbatim:)` accessibility label, the uppercased caption,
    // and `formatCents` all assume USD + English; revisit as a single
    // unit when we expand to a market where any of these break (most
    // likely Japan, where the grader code is still Latin but the
    // surrounding copy is not).

    /// Three discrete display states for the hero number. `.confident` is
    /// the reconciled headline (server-side average of PPT + Poketrace, or
    /// single-source). `.estimated` walks an *intra-grader* descending
    /// ladder to surface the nearest-grade sale price within the same
    /// grader — so a PSA 10 with no PSA 10 sales but a PSA 9 cell at
    /// $6,800 still gets a hero number ("~$6,800") instead of an em-dash.
    /// `.unavailable` fires when neither reconciled nor any same-grader
    /// ladder tier exists.
    enum HeroValue: Equatable {
        case confident(cents: Int64)
        case estimated(cents: Int64, sourceTier: String)
        case unavailable
    }

    var heroValue: HeroValue {
        if let cents = scan.reconciledHeadlinePriceCents {
            return .confident(cents: cents)
        }
        if let nearest = nearestLadderTier() {
            return .estimated(cents: nearest.cents, sourceTier: nearest.label)
        }
        return .unavailable
    }

    private var heroRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                heroNumber
                Text(heroCaption)
                    .font(SlabFont.sans(size: 11, weight: .medium))
                    .tracking(2.0)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.dim)
            }
            Spacer()
        }
        // The hero number animates whenever `heroValue` flips — covers
        // both "reconciled arrives" and "ladder arrives with a sibling
        // tier" transitions. Watching only `reconciledHeadlinePriceCents`
        // missed the latter (snap-cut from "—" to "~$6,800").
        .animation(.easeInOut(duration: 0.25), value: heroValue)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: heroAccessibilityLabel))
    }

    /// Extracted so we can layer `.contentTransition(.numericText())` —
    /// SwiftUI's implicit animation snap-cuts plain `Text` content; the
    /// numeric transition cross-fades digits as the value changes.
    private var heroNumber: some View {
        Text(heroText)
            .font(SlabFont.serif(size: 40))
            .tracking(-1)
            .foregroundStyle(heroColor)
            .contentTransition(.numericText())
    }

    private var heroText: String {
        switch heroValue {
        case .confident(let cents):  return formatCents(cents)
        case .estimated(let cents, _): return "~\(formatCents(cents))"
        case .unavailable: return "—"
        }
    }

    private var heroColor: Color {
        switch heroValue {
        case .confident: return AppColor.text
        case .estimated: return AppColor.muted
        case .unavailable: return AppColor.dim
        }
    }

    private var heroCaption: String {
        switch heroValue {
        case .confident: return reconciledCaption
        case .estimated(_, let source):
            let graderTier = "\(scan.grader.rawValue) \(scan.grade ?? "")"
                .trimmingCharacters(in: .whitespaces)
            let graderUpper = graderTier.uppercased()
            return "ESTIMATE FROM \(source.uppercased()) · NO \(graderUpper) SALES YET"
        case .unavailable: return "NO PRICE DATA"
        }
    }

    /// VoiceOver reads the tilde as punctuation; replace it with the word
    /// "Approximately" so the estimate state is unambiguous over audio.
    private var heroAccessibilityLabel: String {
        switch heroValue {
        case .confident(let cents):
            return "\(formatCents(cents)). \(reconciledCaption.capitalized)."
        case .estimated(let cents, let source):
            let graderTier = "\(scan.grader.rawValue) \(scan.grade ?? "")"
                .trimmingCharacters(in: .whitespaces)
            return "Approximately \(formatCents(cents)). Estimate from \(source). No \(graderTier) sales yet."
        case .unavailable:
            return "No price data."
        }
    }

    /// Walk an *intra-grader* descending ladder to find the nearest tier
    /// with a value when the scan's own (grader, grade) cell is empty.
    /// Prefers PPT's typed columns over Poketrace's JSON-encoded map
    /// because the typed columns are more reliable. The headline tier
    /// itself is skipped — if it had a value, `reconciledHeadlinePriceCents`
    /// would already be set and we wouldn't be on this path.
    ///
    /// **Why intra-grader only?** Cross-grader walks pick "first tier
    /// with data" rather than "nearest market value" — and graders
    /// trade at very different premiums (BGS Black Label ≫ PSA 10 ≫
    /// CGC 10 for the same card). Showing a PSA 10 estimate on a BGS 10
    /// scan would lowball the dealer's offer. Conservative direction:
    /// estimates only from the same grader, descending. If the
    /// same-grader ladder is empty, the user sets a manual price or
    /// refreshes comp — both are explicit dealer actions, not
    /// silently-wrong defaults.
    /// (PPT, Poketrace) tier-id → tier lookups for the adjacency walk.
    /// Returned as a tuple so a single walk over the ladder arrays
    /// builds both maps — `nearestLadderTier()` and any future caller
    /// that needs adjacency pays one allocation per body re-eval, not
    /// two. This is on the hot path because `heroValue` is evaluated
    /// multiple times per body invocation. Defensive
    /// `uniquingKeysWith` because `Dictionary(uniqueKeysWithValues:)`
    /// traps on duplicate ids — should never happen with our fixed
    /// ladder layout, but a snapshot mutation across @Model accessors
    /// could in theory produce one; prefer not to crash the comp card.
    private var ladderLookups: (ppt: [String: Tier], poketrace: [String: Tier]) {
        let pptById = Dictionary(pptLadderTiers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ptById  = Dictionary(poketraceLadderTiers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (pptById, ptById)
    }

    func nearestLadderTier() -> (cents: Int64, label: String)? {
        let service = scan.grader.rawValue
        let grade = scan.grade ?? ""
        let candidates = adjacencyCandidates(service: service, grade: grade)
        let lookups = ladderLookups
        for candidateId in candidates {
            if let tier = lookups.ppt[candidateId]      { return (tier.cents, tier.label) }
            if let tier = lookups.poketrace[candidateId] { return (tier.cents, tier.label) }
        }
        return nil
    }

    /// Adjacency: ordered list of ladder ids *within the same grader*
    /// descending from the scan's grade. The headline tier itself is
    /// omitted (covered by the reconciled path). Hardcoded — small,
    /// legible, no novel data structure.
    private func adjacencyCandidates(service: String, grade: String) -> [String] {
        switch (service, grade) {
        case ("PSA", "10"):
            return ["psa_9_5", "psa_9", "psa_8", "psa_7"]
        case ("PSA", "9.5"):
            return ["psa_9", "psa_8", "psa_7"]
        case ("PSA", "9"):
            return ["psa_9_5", "psa_8", "psa_7"]
        case ("PSA", "8"):
            return ["psa_9", "psa_9_5", "psa_7"]
        case ("PSA", "7"):
            return ["psa_8", "psa_9"]
        // BGS / CGC / SGC ladders only carry the top tier (`*_10`) in
        // our snapshot schema today, so there is no intra-grader
        // sibling to walk to. Return [] so the caller falls through
        // to `.unavailable` — the user refreshes comp or sets a manual
        // price rather than getting a cross-grader estimate.
        case ("BGS", _), ("CGC", _), ("SGC", _), ("TAG", _):
            return []
        default:
            return []
        }
    }

    private var reconciledHeadlineText: String {
        guard let cents = scan.reconciledHeadlinePriceCents else { return "—" }
        return formatCents(cents)
    }

    /// Caption beneath the hero. Prefers `scan.reconciledSource` (set by
    /// the server-side reconciliation rule) and falls back to inferring
    /// from snapshot presence for legacy rows that pre-date the source
    /// being plumbed through.
    private var reconciledCaption: String {
        let graderTier = "\(scan.grader.rawValue) \(scan.grade ?? "")".trimmingCharacters(in: .whitespaces)
        let suffix = graderTier.isEmpty ? "" : " · \(graderTier)"
        let lead: String
        switch scan.reconciledSource {
        case "avg":
            lead = "avg of 2 sources"
        case "ppt-only":
            lead = "PPT only"
        case "poketrace-only":
            lead = "Poketrace only"
        case "poketrace-preferred":
            // Surface the sale count so the operator sees *why* Poketrace
            // wins over the simple average — "n=57" makes the override
            // legible without explaining the rule in copy.
            if let n = poketraceSnapshot?.ptSaleCount {
                return "Poketrace · n=\(n)\(suffix)"
            }
            lead = "Poketrace preferred"
        default:
            // Legacy fallback when reconciledSource hasn't been written.
            let pptOK = pptSnapshot?.headlinePriceCents != nil
            let ptOK  = poketraceSnapshot?.ptAvgCents != nil
            switch (pptOK, ptOK) {
            case (true,  true):  lead = "avg of 2 sources"
            case (true,  false): lead = "PPT only"
            case (false, true):  lead = "Poketrace only"
            case (false, false): return "no price data"
            }
        }
        return "\(lead)\(suffix)"
    }

    // MARK: - Sources strip

    private var sourcesRow: some View {
        HStack(alignment: .top, spacing: Spacing.l) {
            SourcePriceCell(
                title: "PPT",
                priceCents: pptSnapshot?.headlinePriceCents,
                accessoryLine1: nil,
                accessoryLine2: nil,
                confidence: nil
            )
            Rectangle()
                .fill(AppColor.hairline)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            SourcePriceCell(
                title: "Poketrace",
                priceCents: poketraceSnapshot?.ptAvgCents,
                accessoryLine1: priceRange(snapshot: poketraceSnapshot),
                accessoryLine2: salesAndTrend(snapshot: poketraceSnapshot),
                confidence: poketraceSnapshot?.ptConfidence
            )
        }
        // Fixed minimum so a thin Poketrace cell (no range / no count)
        // doesn't collapse the divider against the PPT cell.
        .frame(minHeight: 44)
    }

    private func priceRange(snapshot: GradedMarketSnapshot?) -> String? {
        guard let s = snapshot, let lo = s.ptLowCents, let hi = s.ptHighCents else { return nil }
        return "\(formatCentsCompact(lo))–\(formatCentsCompact(hi))"
    }

    private func salesAndTrend(snapshot: GradedMarketSnapshot?) -> String? {
        guard let s = snapshot else { return nil }
        var parts: [String] = []
        if let n = s.ptSaleCount { parts.append("n=\(n)") }
        if let trend = s.ptTrend { parts.append(trendChevron(trend)) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func trendChevron(_ trend: String) -> String {
        switch trend {
        case "up":   return "▲"
        case "down": return "▼"
        default:     return "–"
        }
    }

    // MARK: - Source toggle + sparkline

    // Sorted once per snapshot identity in `refreshSortedHistories()`;
    // these accessors just read the cached arrays so a body re-eval
    // doesn't re-sort on the hot path.
    private var pptHistoryPoints: [PriceHistoryPoint] {
        pptSortedHistory
    }

    private var poketraceHistoryPoints: [PriceHistoryPoint] {
        poketraceSortedHistory
    }

    private var activeSparklinePoints: [PriceHistoryPoint] {
        switch sparklineSource {
        case .ppt:       return pptHistoryPoints
        case .poketrace: return poketraceHistoryPoints
        }
    }

    /// Show the toggle only when both providers have something the user
    /// could actually be flipping between — either ladder data or
    /// sparkline history. With one source missing, the cells already
    /// degrade to "—" and a toggle would be misleading.
    private var showsSourceToggle: Bool {
        let pptHas = pptSnapshot != nil && (!pptHistoryPoints.isEmpty || !pptLadderTiers.isEmpty)
        let ptHas  = poketraceSnapshot != nil && (!poketraceHistoryPoints.isEmpty || !poketraceLadderTiers.isEmpty)
        return pptHas && ptHas
    }

    private var sourceTogglePicker: some View {
        Picker("Comp source", selection: $sparklineSource) {
            Text("PPT").tag(SparklineSource.ppt)
            Text("Poketrace").tag(SparklineSource.poketrace)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Comp source")
    }

    /// If the currently-selected source has no ladder AND no history but
    /// the other does, swap to the populated one so the operator never
    /// stares at a card full of "—" and an empty chart.
    private func reconcileActiveSource() {
        let pptEmpty = pptHistoryPoints.isEmpty && pptLadderTiers.isEmpty
        let ptEmpty  = poketraceHistoryPoints.isEmpty && poketraceLadderTiers.isEmpty
        if sparklineSource == .ppt, pptEmpty, !ptEmpty {
            sparklineSource = .poketrace
        } else if sparklineSource == .poketrace, ptEmpty, !pptEmpty {
            sparklineSource = .ppt
        }
    }

    enum SparklineSource: String, CaseIterable, Identifiable {
        case ppt, poketrace
        var id: String { rawValue }
    }

    // MARK: - Grade ladder (PPT-shaped)

    private struct Tier: Identifiable {
        let id: String
        let label: String
        let cents: Int64
        let isHeadline: Bool
    }

    /// Canonical ladder layout: Raw at the front, then highest grades
    /// descending within each grading company (PSA → CGC → BGS → SGC).
    /// Both PPT and Poketrace render against this single ordering so
    /// the toggle swaps values without reflowing cells.
    ///
    /// CGC's "Pristine 10" is bundled into `CGC_10` by both Poketrace
    /// and PPT — neither source distinguishes Gem Mint 10 from Pristine
    /// 10, so the rail has a single CGC 10 cell.
    private static let ladderLayout: [(id: String, label: String, headlineKey: (service: String, grade: String)?)] = [
        ("loose",    "Raw",     nil),
        ("psa_10",   "PSA 10",  ("PSA", "10")),
        ("psa_9_5",  "PSA 9.5", ("PSA", "9.5")),
        ("psa_9",    "PSA 9",   ("PSA", "9")),
        ("psa_8",    "PSA 8",   ("PSA", "8")),
        ("psa_7",    "PSA 7",   ("PSA", "7")),
        ("cgc_10",   "CGC 10",  ("CGC", "10")),
        ("bgs_10",   "BGS 10",  ("BGS", "10")),
        ("sgc_10",   "SGC 10",  ("SGC", "10")),
    ]

    /// Tiers from the PPT snapshot's typed columns. Returns `[]` when
    /// the PPT snapshot is missing.
    private var pptLadderTiers: [Tier] {
        guard let snapshot = pptSnapshot else { return [] }
        let cents: [String: Int64?] = [
            "loose":   snapshot.loosePriceCents,
            "psa_7":   snapshot.psa7PriceCents,
            "psa_8":   snapshot.psa8PriceCents,
            "psa_9":   snapshot.psa9PriceCents,
            "psa_9_5": snapshot.psa9_5PriceCents,
            "psa_10":  snapshot.psa10PriceCents,
            "bgs_10":  snapshot.bgs10PriceCents,
            "cgc_10":  snapshot.cgc10PriceCents,
            "sgc_10":  snapshot.sgc10PriceCents,
        ]
        return Self.ladderLayout.compactMap { layout in
            guard let optCents = cents[layout.id], let c = optCents else { return nil }
            let isHeadline = layout.headlineKey.map {
                $0.service == snapshot.gradingService && $0.grade == snapshot.grade
            } ?? false
            return Tier(id: layout.id, label: layout.label, cents: c, isHeadline: isHeadline)
        }
    }

    /// Tiers from the Poketrace snapshot's JSON-encoded ladder map.
    /// Same ordering as the PPT side so the toggle just swaps values
    /// without reflowing the rail.
    private var poketraceLadderTiers: [Tier] {
        guard let snapshot = poketraceSnapshot else { return [] }
        let prices = snapshot.ptTierPricesCents
        return Self.ladderLayout.compactMap { layout in
            guard let cents = prices[layout.id] else { return nil }
            let isHeadline = layout.headlineKey.map {
                $0.service == snapshot.gradingService && $0.grade == snapshot.grade
            } ?? false
            return Tier(id: layout.id, label: layout.label, cents: cents, isHeadline: isHeadline)
        }
    }

    /// Ordered tiers in the ladder rail, sourced from whichever provider
    /// the toggle currently points at. The cell matching the scan's
    /// (gradingService, grade) gets a gold border.
    private var ladderTiers: [Tier] {
        switch sparklineSource {
        case .ppt:       return pptLadderTiers
        case .poketrace: return poketraceLadderTiers
        }
    }

    private var ladderRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(ladderTiers) { tier in
                    tierCell(tier)
                }
            }
        }
    }

    private func tierCell(_ tier: Tier) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(tier.label)
                .font(SlabFont.sans(size: 10, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(AppColor.dim)
            Text(formatCentsCompact(tier.cents))
                .font(SlabFont.mono(size: 14, weight: .medium))
                .foregroundStyle(AppColor.text)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.s)
                .stroke(tier.isHeadline ? AppColor.gold : AppColor.dim.opacity(0.3),
                        lineWidth: tier.isHeadline ? 1.5 : 1)
        )
    }

    // MARK: - Caveat (PPT-driven)

    /// One of three states: stale fallback, headline tier missing for a
    /// supported (grader, grade), or unsupported (grader, grade) entirely.
    /// Driven by the PPT snapshot — Poketrace gracefully degrades inside
    /// its source cell instead.
    private var caveatMessage: String? {
        guard let snapshot = pptSnapshot else { return nil }
        if snapshot.isStaleFallback {
            return "Cached — Pokemon Price Tracker unavailable"
        }
        if snapshot.headlinePriceCents == nil {
            // Distinguish "supported but no value" (PSA 10 with no sales)
            // from "unsupported (TAG / sub-PSA-7)".
            if isSupportedTier(service: snapshot.gradingService, grade: snapshot.grade) {
                return "Pokemon Price Tracker has no \(snapshot.gradingService) \(snapshot.grade) sales for this card yet — showing the rest of the ladder."
            } else {
                return "Pokemon Price Tracker hasn't logged \(snapshot.gradingService) \(snapshot.grade) sales — showing the rest of the ladder."
            }
        }
        return nil
    }

    private func isSupportedTier(service: String, grade: String) -> Bool {
        switch (service, grade) {
        case ("PSA", "10"), ("PSA", "9.5"), ("PSA", "9"), ("PSA", "8"), ("PSA", "7"):
            return true
        case ("BGS", "10"), ("CGC", "10"), ("SGC", "10"):
            return true
        default:
            return false
        }
    }

    private func caveatRow(_ message: String) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: (pptSnapshot?.isStaleFallback ?? false) ? "wifi.slash" : "info.circle")
                .font(SlabFont.sans(size: 12, weight: .medium))
                .foregroundStyle((pptSnapshot?.isStaleFallback ?? false) ? AppColor.negative : AppColor.dim)
            Text(message)
                .font(SlabFont.sans(size: 12, weight: .medium))
                .foregroundStyle((pptSnapshot?.isStaleFallback ?? false) ? AppColor.negative : AppColor.dim)
            Spacer()
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerRow: some View {
        if let url = pptSnapshot?.pptURL {
            Link(destination: url) {
                HStack(spacing: Spacing.xxs) {
                    Text("Powered by Pokemon Price Tracker · View card")
                        .font(SlabFont.sans(size: 12, weight: .medium))
                        .foregroundStyle(AppColor.gold)
                    Image(systemName: "arrow.up.right")
                        .font(SlabFont.sans(size: 11, weight: .medium))
                        .foregroundStyle(AppColor.gold)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack {
                Text("Comp data from Pokemon Price Tracker + Poketrace")
                    .font(SlabFont.sans(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.dim)
                Spacer()
            }
        }
    }

    // MARK: - Formatters

    // i18n deferred — locale is pinned to `en_US` so the surrounding
    // English copy and `$` glyph stay coherent. See the "i18n deferred"
    // note on the hero block.

    /// Compact (0-fraction-digit) USD formatter. Kept distinct from the
    /// shared `Currency.usdFormatter` (which defaults to en_US's 2-digit
    /// behavior) because mutating shared state would regress every other
    /// caller. Cached once per process via `static let`.
    private static let usdCompactFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f
    }()

    fileprivate static func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        return Currency.usdFormatter.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }

    fileprivate static func formatCentsCompact(_ cents: Int64) -> String {
        let dollars = Int((Double(cents) / 100).rounded())
        return Self.usdCompactFormatter.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }

    private func formatCents(_ cents: Int64) -> String { Self.formatCents(cents) }
    private func formatCentsCompact(_ cents: Int64) -> String { Self.formatCentsCompact(cents) }
}

// MARK: - Source price cell

/// One column of the side-by-side sources strip. Renders gracefully
/// when the source has no data (`—` + "no data" in dim).
private struct SourcePriceCell: View {
    let title: String
    let priceCents: Int64?
    let accessoryLine1: String?
    let accessoryLine2: String?
    /// Poketrace-only "high" / "medium" / "low". Tints the price text.
    let confidence: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(SlabFont.sans(size: 10, weight: .medium))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.dim)
            if let cents = priceCents {
                Text(CompCardView.formatCents(cents))
                    .font(SlabFont.mono(size: 18, weight: .semibold))
                    .foregroundStyle(priceColor)
            } else {
                Text("—")
                    .font(SlabFont.mono(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.dim)
                Text("no data")
                    .font(SlabFont.sans(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.dim)
            }
            if let l1 = accessoryLine1 {
                Text(l1)
                    .font(SlabFont.mono(size: 11, weight: .regular))
                    .foregroundStyle(AppColor.muted)
            }
            if let l2 = accessoryLine2 {
                Text(l2)
                    .font(SlabFont.sans(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Confidence-based price tint. We never grey out below `muted` —
    /// this is a working tool, the price still has to read first.
    private var priceColor: Color {
        switch confidence {
        case "high":   return AppColor.text
        case "medium": return AppColor.text.opacity(0.85)
        case "low":    return AppColor.muted
        default:       return AppColor.text
        }
    }
}

// MARK: - Previews

#Preview("Both sources · PSA 10") {
    let history: [PriceHistoryPoint] = (0..<10).map { i in
        let interval: TimeInterval = TimeInterval(-i * 86_400 * 18)
        let price: Int64 = Int64(18_500 - i * 200)
        return PriceHistoryPoint(ts: Date(timeIntervalSinceNow: interval), priceCents: price)
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let json = String(data: (try? encoder.encode(history)) ?? Data(), encoding: .utf8)
    let identityId = UUID()
    let scan = Scan(
        id: UUID(), storeId: UUID(), lotId: UUID(), userId: UUID(),
        grader: .PSA, certNumber: "12345678",
        grade: "10",
        gradedCardIdentityId: identityId,
        status: .validated,
        createdAt: Date(), updatedAt: Date()
    )
    scan.reconciledHeadlinePriceCents = 18_750
    let ppt = GradedMarketSnapshot(
        identityId: identityId, gradingService: "PSA", grade: "10",
        source: GradedMarketSnapshot.sourcePPT,
        headlinePriceCents: 18500, loosePriceCents: 400,
        psa7PriceCents: 2400, psa8PriceCents: 3400, psa9PriceCents: 6800,
        psa9_5PriceCents: 11200, psa10PriceCents: 18500,
        bgs10PriceCents: 21500, cgc10PriceCents: 16800, sgc10PriceCents: 16500,
        pptTCGPlayerId: "243172",
        pptURL: URL(string: "https://www.pokemonpricetracker.com/card/charizard-base-set"),
        priceHistoryJSON: json,
        fetchedAt: Date(), cacheHit: false, isStaleFallback: false
    )
    let pt = GradedMarketSnapshot(
        identityId: identityId, gradingService: "PSA", grade: "10",
        source: GradedMarketSnapshot.sourcePoketrace,
        headlinePriceCents: 19_000,
        ptAvgCents: 19_000, ptLowCents: 17_500, ptHighCents: 21_000,
        ptTrend: "up", ptConfidence: "high", ptSaleCount: 14,
        priceHistoryJSON: json,
        fetchedAt: Date(), cacheHit: false, isStaleFallback: false
    )
    return CompCardView(scan: scan, pptSnapshot: ppt, poketraceSnapshot: pt)
        .padding().background(AppColor.ink)
}

#Preview("PPT only · BGS 10") {
    let identityId = UUID()
    let scan = Scan(
        id: UUID(), storeId: UUID(), lotId: UUID(), userId: UUID(),
        grader: .BGS, certNumber: "98765432",
        grade: "10",
        gradedCardIdentityId: identityId,
        status: .validated,
        createdAt: Date(), updatedAt: Date()
    )
    scan.reconciledHeadlinePriceCents = 21_500
    let ppt = GradedMarketSnapshot(
        identityId: identityId, gradingService: "BGS", grade: "10",
        source: GradedMarketSnapshot.sourcePPT,
        headlinePriceCents: 21500, loosePriceCents: 400,
        psa7PriceCents: nil, psa8PriceCents: nil, psa9PriceCents: nil,
        psa9_5PriceCents: nil, psa10PriceCents: 18500,
        bgs10PriceCents: 21500, cgc10PriceCents: 16800, sgc10PriceCents: nil,
        pptTCGPlayerId: "243172",
        pptURL: URL(string: "https://www.pokemonpricetracker.com/card/charizard-base-set"),
        priceHistoryJSON: nil,
        fetchedAt: Date(), cacheHit: false, isStaleFallback: false
    )
    return CompCardView(scan: scan, pptSnapshot: ppt, poketraceSnapshot: nil)
        .padding().background(AppColor.ink)
}

#Preview("Poketrace only · PSA 9") {
    let identityId = UUID()
    let scan = Scan(
        id: UUID(), storeId: UUID(), lotId: UUID(), userId: UUID(),
        grader: .PSA, certNumber: "55555555",
        grade: "9",
        gradedCardIdentityId: identityId,
        status: .validated,
        createdAt: Date(), updatedAt: Date()
    )
    scan.reconciledHeadlinePriceCents = 6_800
    let pt = GradedMarketSnapshot(
        identityId: identityId, gradingService: "PSA", grade: "9",
        source: GradedMarketSnapshot.sourcePoketrace,
        headlinePriceCents: 6_800,
        ptAvgCents: 6_800, ptLowCents: 6_100, ptHighCents: 7_400,
        ptTrend: "stable", ptConfidence: "medium", ptSaleCount: 6,
        priceHistoryJSON: nil,
        fetchedAt: Date(), cacheHit: false, isStaleFallback: false
    )
    return CompCardView(scan: scan, pptSnapshot: nil, poketraceSnapshot: pt)
        .padding().background(AppColor.ink)
}
