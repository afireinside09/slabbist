import SwiftUI
import SwiftData
import OSLog
import Supabase
import Auth

struct ScanDetailView: View {
    let scan: Scan
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(OutboxKicker.self) private var kicker
    @Environment(Reachability.self) private var reachability
    @Query private var snapshots: [GradedMarketSnapshot]
    @Query private var identities: [GradedCardIdentity]
    @State private var showingManualPrice = false
    @State private var showingBuyPriceSheet = false

    init(scan: Scan) {
        self.scan = scan
        let identityId = scan.gradedCardIdentityId ?? UUID()
        let service = scan.grader.rawValue
        let grade = scan.grade ?? ""
        _snapshots = Query(filter: #Predicate<GradedMarketSnapshot> { s in
            s.identityId == identityId &&
            s.gradingService == service &&
            s.grade == grade
        }, sort: \GradedMarketSnapshot.fetchedAt, order: .reverse)
        // Filtering by id avoids loading every identity in the store
        // just to render one detail screen.
        _identities = Query(filter: #Predicate<GradedCardIdentity> { $0.id == identityId })
    }

    private var identity: GradedCardIdentity? { identities.first }

    /// PPT row for this slab. Two snapshots can coexist per
    /// `(identityId, service, grade)` — one per source — so we partition
    /// the `@Query` results by `source` here and pass both into
    /// `CompCardView` for side-by-side rendering.
    private var pptSnapshot: GradedMarketSnapshot? {
        snapshots.first { $0.source == GradedMarketSnapshot.sourcePPT }
    }

    /// Poketrace row for this slab. `nil` when the Poketrace branch had
    /// no match or its API key is unset / failing — `CompCardView`
    /// renders "no data" in that column rather than hiding the surface.
    private var poketraceSnapshot: GradedMarketSnapshot? {
        snapshots.first { $0.source == GradedMarketSnapshot.sourcePoketrace }
    }

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    scanFrozenBanner
                    header
                    buyPriceCard
                    if pptSnapshot != nil || poketraceSnapshot != nil {
                        valueSection
                    } else {
                        fallbackContent
                    }
                    if scan.vendorAskCents != nil {
                        manualPriceCard
                    }
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingManualPrice) {
            ManualPriceSheet(initialCents: scan.vendorAskCents) { cents in
                try setOfferCents(cents)
            }
        }
        .sheet(isPresented: $showingBuyPriceSheet) {
            BuyPriceSheet(initialCents: scan.buyPriceCents) { cents in
                try offerRepository().setBuyPrice(cents, scan: scan, overridden: cents != nil)
            }
        }
        // Recovery hatch for two real-world stuck states:
        //   1. The scan was validated in a prior session and never had a
        //      comp fetched (state = nil) — bulk scan exited too soon.
        //   2. State is `.fetching` but the in-memory `inFlight` task
        //      from `CompFetchService` was lost when the app was killed,
        //      so the spinner is a ghost with nothing behind it.
        // Both manifest as "Pulling eBay listings…" forever with
        // no retry CTA — kicking a fresh fetch on appear unblocks them.
        .task(id: scan.id) {
            autoTriggerCompFetchIfNeeded()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel(headerKicker)
            Text(headerTitle)
                .slabTitle()
                .lineLimit(2)
            if let setLine = headerSetLine {
                Text(setLine)
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.muted)
            }
            Text(headerSubtitle)
                .font(SlabFont.mono(size: 12))
                .foregroundStyle(AppColor.muted)
        }
    }

    /// Kicker reads as "PSA 10" so the eye lands on the slab tier
    /// before the card name, matching the queue rows. Falls back to
    /// the bare grader when no grade has landed yet.
    private var headerKicker: String {
        if let grade = scan.grade, !grade.isEmpty {
            return "\(scan.grader.rawValue) \(grade)"
        }
        return scan.grader.rawValue
    }

    private var headerTitle: String {
        if let identity {
            if let n = identity.cardNumber, !n.isEmpty {
                return "\(identity.cardName) #\(n)"
            }
            return identity.cardName
        }
        // Pre-validation fallback so the view doesn't render an empty
        // big-text region while cert lookup is still in flight.
        if let grade = scan.grade, !grade.isEmpty {
            return "\(scan.grader.rawValue) \(grade)"
        }
        return scan.grader.rawValue
    }

    /// Year + set + variant in the same shape used by the lot row.
    /// `nil` while the identity hasn't been persisted yet so the
    /// header stays compact.
    private var headerSetLine: String? {
        guard let identity else { return nil }
        var parts: [String] = []
        if let year = identity.year { parts.append(String(year)) }
        parts.append(identity.setName)
        if let v = identity.variant, !v.isEmpty { parts.append(v) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var headerSubtitle: String { "Cert #\(scan.certNumber)" }

    // MARK: - Value section (resolved)

    private var valueSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Market value")
            CompCardView(
                scan: scan,
                pptSnapshot: pptSnapshot,
                poketraceSnapshot: poketraceSnapshot
            )
            if let attemptedAt = scan.compFetchedAt {
                Text("Last refreshed \(attemptedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(SlabFont.mono(size: 11))
                    .foregroundStyle(AppColor.dim)
            }
            PrimaryGoldButton(title: "Refresh comp", action: retry)
        }
    }

    // MARK: - State machine (no snapshot)

    @ViewBuilder
    private var fallbackContent: some View {
        if scan.gradedCardIdentityId == nil {
            certNotResolvedState
        } else {
            switch scan.compFetchState.flatMap(CompFetchState.init(rawValue:)) {
            case .resolved:
                // Resolved but the @Query hasn't picked up the snapshot yet
                // (millisecond race) — show progress, it'll flip in a tick.
                fetchingState
            case .noData:
                noDataState
            case .failed:
                failedState
            case .fetching, .none:
                fetchingState
            }
        }
    }

    private var fetchingState: some View {
        emptyState(
            kicker: "Fetching",
            symbol: "arrow.triangle.2.circlepath",
            symbolTint: AppColor.gold,
            title: "Fetching Pokemon Price Tracker comp…",
            detail: "This usually takes a couple of seconds. Tap retry if it's stuck.",
            showsProgress: true,
            cta: ("Retry comp fetch", retry)
        )
    }

    /// Empty / error state for scans that haven't yet resolved a graded card
    /// identity. Forks on `(scan.status, scan.validationFailureReason)`:
    ///   - In-flight lookup: "Validating cert…" spinner, no CTA.
    ///   - Transient failure (offline / 5xx / cancellation): "Couldn't reach
    ///     PSA" with a retry CTA — the user's escape from the pre-C1 hang.
    ///   - `not_found`: terminal "delete and rescan" path.
    ///   - `not_pokemon`: terminal "manual price" path.
    ///
    /// `@ViewBuilder` (not `AnyView`) so SwiftUI's structural diff sees
    /// the four concrete branches and re-uses identity across re-renders.
    /// `AnyView` erases the structural type and would force full subtree
    /// rebuilds on every Scan mutation (P1.5).
    @ViewBuilder
    private var certNotResolvedState: some View {
        let reason = scan.validationFailureReason
        let isTransient = reason == "transient"
        let isFailedTerminal = scan.status == .validationFailed && !isTransient
        let isNotPokemon = reason == "not_pokemon"

        if isTransient {
            transientCertLookupState
        } else if isNotPokemon {
            notPokemonState
        } else if isFailedTerminal {
            notFoundState
        } else {
            validatingCertState
        }
    }

    /// In-flight cert lookup — the only state that legitimately spins. No
    /// retry CTA: the user just has to wait.
    private var validatingCertState: some View {
        emptyState(
            kicker: "Validating",
            symbol: "hourglass",
            symbolTint: AppColor.gold,
            title: "Validating cert…",
            detail: "Once PSA confirms the cert, eBay listings will load automatically.",
            showsProgress: true,
            cta: nil,
            lastAttemptAt: nil,
            footerDetail: nil
        )
    }

    /// Terminal: PSA returned `CERT_NOT_FOUND`. Recourse is delete-and-rescan.
    private var notFoundState: some View {
        emptyState(
            kicker: "Cert not found",
            symbol: "exclamationmark.circle",
            symbolTint: AppColor.negative,
            title: "PSA didn't recognize this cert",
            detail: "Cert #\(scan.certNumber) isn't in PSA's database. The digits on the slab may have been misread — delete this scan and try again.",
            showsProgress: false,
            cta: nil,
            lastAttemptAt: scan.validationLastAttemptAt,
            footerDetail: nil
        )
    }

    /// Terminal: cert resolves to a non-Pokemon product. Slabbist comps are
    /// Pokemon-only — recourse is set-manual-price (gold CTA so the lot total
    /// stays accurate).
    private var notPokemonState: some View {
        emptyState(
            kicker: "Different game",
            symbol: "questionmark.square.dashed",
            symbolTint: AppColor.muted,
            title: "This slab isn't a Pokémon card",
            detail: "Slabbist comps are Pokémon-only. You can still set a manual price to keep this slab in the lot total.",
            showsProgress: false,
            cta: scan.vendorAskCents == nil ? ("Set manual price", { showingManualPrice = true }) : nil,
            lastAttemptAt: scan.validationLastAttemptAt,
            footerDetail: nil
        )
    }

    /// Transient cert-lookup failure (network / 5xx / cancellation / offline).
    /// Primary CTA is "Retry cert lookup" (gold). Secondary is set-manual-price
    /// so the operator can still ship the lot if PSA stays unreachable.
    /// After >=3 attempts we surface a network hint in the detail copy.
    private var transientCertLookupState: some View {
        let hint = scan.validationAttemptCount >= 3
            ? " Check your connection — we've tried \(scan.validationAttemptCount) times."
            : ""
        return emptyState(
            kicker: "Couldn't reach PSA",
            symbol: "wifi.exclamationmark",
            symbolTint: AppColor.negative,
            title: "PSA lookup failed",
            detail: "We couldn't reach PSA to verify cert #\(scan.certNumber). Tap retry to try again.\(hint)",
            showsProgress: false,
            cta: ("Retry cert lookup", retryCertLookup),
            lastAttemptAt: scan.validationLastAttemptAt,
            footerDetail: scan.vendorAskCents == nil ? ("Set manual price", { showingManualPrice = true }) : nil
        )
    }

    /// Re-fires the cert lookup from the detail screen. Needs a viewModel
    /// scoped to this scan's lot — we build a fresh one because the detail
    /// view doesn't carry the bulk-scan VM in environment.
    ///
    /// Forwards the env-injected `Reachability` so the detail-screen retry
    /// honors offline the same way the queue-row retry does (P0.2). Without
    /// this, a user tapping the gold "Retry cert lookup" CTA while offline
    /// gets the generic transient copy instead of the clean
    /// "Offline — will retry when connected" message.
    private func retryCertLookup() {
        let functionsBaseURL = AppEnvironment.supabaseURL.appendingPathComponent("/functions/v1")
        let tokenProvider: () async -> String? = {
            try? await AppSupabase.shared.client.auth.session.accessToken
        }
        let cert = CertLookupRepository(baseURL: functionsBaseURL, authTokenProvider: tokenProvider)
        guard let lot = lookupLot() else {
            AppLog.scans.error("retry cert lookup: parent lot missing")
            return
        }
        let reach = self.reachability
        let vm = BulkScanViewModel(
            context: context,
            kicker: kicker,
            lot: lot,
            currentUserId: session.userId ?? UUID(),
            compRepository: nil,
            certLookupRepository: cert,
            reachabilityStatus: { reach.status }
        )
        vm.retryValidation(scan: scan)
    }

    private var noDataState: some View {
        emptyState(
            kicker: "No comp",
            symbol: "magnifyingglass",
            symbolTint: AppColor.muted,
            title: "Pokemon Price Tracker has no comp for this slab",
            detail: "Either we couldn't find this card on Pokemon Price Tracker, or there's no published price for this tier yet. Set a manual price to count this slab in your lot total.",
            showsProgress: false,
            cta: ("Retry comp fetch", retry),
            secondaryCta: scan.vendorAskCents == nil ? ("Set manual price", { showingManualPrice = true }) : nil
        )
    }

    private var failedState: some View {
        emptyState(
            kicker: "Lookup failed",
            symbol: "exclamationmark.triangle",
            symbolTint: AppColor.negative,
            title: "Comp fetch failed",
            detail: scan.compFetchError ?? "Unknown error",
            showsProgress: false,
            cta: ("Retry comp fetch", retry),
            secondaryCta: scan.vendorAskCents == nil ? ("Set manual price", { showingManualPrice = true }) : nil
        )
    }

    // MARK: - Buy price card

    /// Header card showing the store's current buy price for this slab and an
    /// edit affordance. Sits above the comp surface so the store's price is
    /// the first thing the operator sees — comp is the *why* behind it.
    /// When no buy price has landed yet we still render the card with an em-
    /// dash placeholder so the surface stays predictable across the four
    /// fallback states (fetching / no-comp / failed / resolved).
    private var buyPriceCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Buy price")
            SlabCard {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(scan.buyPriceCents.map(formattedCents) ?? "—")
                            .font(SlabFont.serif(size: 32))
                            .foregroundStyle(AppColor.text)
                        Spacer()
                        Text(buyPriceCaption)
                            .font(SlabFont.mono(size: 11))
                            .foregroundStyle(AppColor.dim)
                    }
                    if lotIsPricingEditable {
                        HStack(spacing: Spacing.m) {
                            Button("Edit") { showingBuyPriceSheet = true }
                                .buttonStyle(.plain)
                                .font(SlabFont.sans(size: 13, weight: .semibold))
                                .foregroundStyle(AppColor.gold)
                                .accessibilityIdentifier("buy-price-edit")
                            if scan.buyPriceOverridden {
                                Button("Reset to auto") {
                                    try? offerRepository().setBuyPrice(nil, scan: scan, overridden: false)
                                }
                                .buttonStyle(.plain)
                                .font(SlabFont.sans(size: 13, weight: .semibold))
                                .foregroundStyle(AppColor.muted)
                                .accessibilityIdentifier("buy-price-reset")
                            }
                        }
                    } else {
                        // Lot is in a terminal/locked offer state — hide
                        // the edit affordances and surface a short status
                        // string so operators understand why.
                        Text("Locked — \(lookupLot()?.lotOfferState ?? "—")")
                            .font(SlabFont.mono(size: 11))
                            .foregroundStyle(AppColor.dim)
                            .accessibilityIdentifier("buy-price-locked")
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.md)
            }
        }
    }

    /// Caption under the buy price hero. Three cases:
    ///   * Overridden → "Override" — the user typed this in.
    ///   * No price yet → "Awaiting comp" — we have nothing to multiply.
    ///   * Auto-derived → "Auto · X% × comp" — surfaces the margin rule the
    ///     value was derived from so the operator can sanity-check the math.
    ///
    /// The displayed percentage comes from the lot's manual override when
    /// set; otherwise it's derived from the actual buy/comp ratio so a
    /// ladder-priced slab shows the tier that fired (e.g. an $1,200 PSA 10
    /// at the 90% tier reads "Auto · 90% × comp" without the view having
    /// to re-walk the ladder).
    private var buyPriceCaption: String {
        if scan.buyPriceOverridden { return "Override" }
        if scan.buyPriceCents == nil { return "Awaiting comp" }
        if let pct = lookupLot()?.marginPctSnapshot {
            return "Auto · \(Int((pct * 100).rounded()))% × comp"
        }
        if let buy = scan.buyPriceCents,
           let comp = scan.reconciledHeadlinePriceCents, comp > 0 {
            let pct = Int((Double(buy) / Double(comp) * 100).rounded())
            return "Auto · \(pct)% × comp"
        }
        return "Auto · ladder × comp"
    }

    /// Builds an `OfferRepository` scoped to this scan's store. Constructed
    /// fresh on each call so SwiftData context + session UUIDs always reflect
    /// "now". The type is cheap to construct.
    private func offerRepository() -> OfferRepository {
        OfferRepository(
            context: context,
            kicker: kicker,
            currentStoreId: scan.storeId,
            currentUserId: session.userId ?? UUID()
        )
    }

    /// Lookup the lot this scan belongs to so the caption can show the
    /// snapshotted margin. Returns `nil` (and the caption falls back to 60%)
    /// for scans whose parent lot can't be fetched — that shouldn't happen
    /// in practice but we don't want to crash a detail screen over it.
    private func lookupLot() -> Lot? {
        let lotId = scan.lotId
        return try? context.fetch(
            FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })
        ).first
    }

    /// True when the parent lot is in a state where the per-scan buy price
    /// can still be edited. Mirrors the guard in `OfferRepository.setBuyPrice`
    /// (which would throw on terminal states); hiding the buttons here makes
    /// the constraint visible instead of producing a silent no-op tap.
    private var lotIsPricingEditable: Bool {
        guard let lot = lookupLot() else { return true }
        let state = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
        return [.drafting, .priced, .presented].contains(state)
    }

    /// True when the parent lot is `.paid` or `.voided` — the slab is part of
    /// a sealed transaction and must read-only. Drives `scanFrozenBanner`.
    private var lotIsTerminal: Bool {
        guard let lot = lookupLot() else { return false }
        let state = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
        return state == .paid || state == .voided
    }

    /// Top-of-page lock strip shown when this scan's parent lot is terminal.
    /// Communicates immutability before the operator scrolls into editing
    /// affordances that are already disabled by `lotIsPricingEditable`.
    @ViewBuilder
    private var scanFrozenBanner: some View {
        if lotIsTerminal {
            SlabCard {
                HStack {
                    Image(systemName: "lock.fill").foregroundStyle(AppColor.gold)
                    Text("Frozen — this scan is part of a paid lot")
                        .font(SlabFont.mono(size: 11, weight: .semibold))
                        .tracking(0.8)
                    Spacer()
                }
                .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
            }
            .accessibilityIdentifier("scan-frozen-banner")
        }
    }

    /// Standalone card showing the manual price the user set when no PPT
    /// comp was available. Rendered in addition to the comp / empty state
    /// so the user can edit or clear the value at any time. Tap-to-edit
    /// presents the same `ManualPriceSheet` used to enter it.
    private var manualPriceCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Manual price")
            SlabCard {
                HStack(alignment: .center, spacing: Spacing.m) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(scan.vendorAskCents.map(formattedCents) ?? "—")
                            .font(SlabFont.mono(size: 22, weight: .semibold))
                            .foregroundStyle(AppColor.text)
                        Text("Counts toward this lot's total")
                            .font(SlabFont.sans(size: 12))
                            .foregroundStyle(AppColor.dim)
                    }
                    Spacer()
                    Button {
                        showingManualPrice = true
                    } label: {
                        Text("Edit")
                            .font(SlabFont.sans(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.gold)
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, Spacing.s)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                                    .stroke(AppColor.gold.opacity(0.45), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit manual price")
                    .accessibilityIdentifier("manual-price-edit")
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.md)
            }
        }
    }

    private func formattedCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        fmt.maximumFractionDigits = cents % 100 == 0 ? 0 : 2
        return fmt.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }

    private func setOfferCents(_ cents: Int64?) throws {
        guard let viewModel = LotsViewModel.resolve(context: context, kicker: kicker, session: session) else {
            AppLog.scans.error("set offer cents: no LotsViewModel — user signed out?")
            return
        }
        try viewModel.setOfferCents(scan: scan, cents: cents)
    }

    /// Shared empty / loading / error layout. Keeps the visual rhythm
    /// consistent across the four state-machine branches.
    ///
    /// `lastAttemptAt` overrides the implicit `scan.compFetchedAt` footer —
    /// the cert-resolution states use `scan.validationLastAttemptAt`
    /// instead because the failure they're describing predates any comp
    /// fetch. Passing `nil` for both keeps the footer hidden.
    ///
    /// `footerDetail` is the alias for `secondaryCta` — kept as a tuple of
    /// `(label, action)` so the call sites read naturally.
    private func emptyState(
        kicker: String,
        symbol: String,
        symbolTint: Color,
        title: String,
        detail: String,
        showsProgress: Bool,
        cta: (label: String, action: () -> Void)?,
        secondaryCta: (label: String, action: () -> Void)? = nil,
        lastAttemptAt: Date? = nil,
        footerDetail: (label: String, action: () -> Void)? = nil
    ) -> some View {
        let resolvedAttemptAt = lastAttemptAt ?? scan.compFetchedAt
        let resolvedSecondary = footerDetail ?? secondaryCta
        return VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel(kicker)
            SlabCard {
                VStack(spacing: Spacing.m) {
                    if showsProgress {
                        ProgressView().tint(AppColor.gold)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 32, weight: .regular))
                            .foregroundStyle(symbolTint)
                    }
                    Text(title)
                        .slabRowTitle()
                        .multilineTextAlignment(.center)
                    Text(detail)
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.muted)
                        .multilineTextAlignment(.center)
                    if let at = resolvedAttemptAt, !showsProgress {
                        Text("Last attempt \(at.formatted(date: .abbreviated, time: .shortened))")
                            .font(SlabFont.mono(size: 11))
                            .foregroundStyle(AppColor.dim)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.xl)
            }
            if let cta {
                PrimaryGoldButton(title: cta.label, action: cta.action)
            }
            if let secondary = resolvedSecondary {
                Button(action: secondary.action) {
                    Text(secondary.label)
                        .font(SlabFont.sans(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                                .stroke(AppColor.gold.opacity(0.55), lineWidth: 1)
                        )
                        .foregroundStyle(AppColor.gold)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("manual-price-cta")
            }
        }
    }

    private func retry() {
        CompFetchService.fetch(scan: scan, repository: CompRepository.live(), context: context, kicker: kicker)
    }

    /// Auto-recover from two real-world stuck states (see `body.task`):
    /// state is `nil` (cert lookup landed but bulk scan exited before
    /// firing comp fetch) or state is `.fetching` but the originating
    /// task is gone (app kill / VM teardown). The stale-fetch detection
    /// lives on `CompFetchService.isStaleFetching` so the same threshold
    /// drives the queue-row + lot-row Retry pills.
    private func autoTriggerCompFetchIfNeeded() {
        guard scan.gradedCardIdentityId != nil else { return }
        // Either source landing means we have *something* to render;
        // only auto-trigger when we have nothing at all.
        guard pptSnapshot == nil && poketraceSnapshot == nil else { return }
        let state = scan.compFetchState.flatMap(CompFetchState.init(rawValue:))
        if state == nil || CompFetchService.isStaleFetching(scan) {
            retry()
        }
    }

}
