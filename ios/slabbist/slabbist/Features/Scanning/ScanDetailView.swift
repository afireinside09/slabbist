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
    @Query private var snapshots: [GradedMarketSnapshot]
    @Query private var identities: [GradedCardIdentity]
    @State private var showingManualPrice = false

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
                    header
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

    private var certNotResolvedState: some View {
        emptyState(
            kicker: scan.status == .validationFailed ? "Cert not found" : "Validating",
            symbol: scan.status == .validationFailed ? "exclamationmark.circle" : "hourglass",
            symbolTint: scan.status == .validationFailed ? AppColor.negative : AppColor.gold,
            title: scan.status == .validationFailed ? "Cert lookup failed" : "Validating cert…",
            detail: scan.status == .validationFailed
                ? "PSA didn't recognize cert \(scan.certNumber). Delete this slab and re-scan if the digits look wrong."
                : "Once PSA confirms the cert, eBay listings will load automatically.",
            showsProgress: scan.status != .validationFailed,
            cta: nil
        )
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
    private func emptyState(
        kicker: String,
        symbol: String,
        symbolTint: Color,
        title: String,
        detail: String,
        showsProgress: Bool,
        cta: (label: String, action: () -> Void)?,
        secondaryCta: (label: String, action: () -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
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
                    if let at = scan.compFetchedAt, !showsProgress {
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
            if let secondaryCta {
                Button(action: secondaryCta.action) {
                    Text(secondaryCta.label)
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
        let baseURL = AppEnvironment.supabaseURL.appendingPathComponent("/functions/v1")
        let repo = CompRepository(
            baseURL: baseURL,
            authTokenProvider: { try? await AppSupabase.shared.client.auth.session.accessToken }
        )
        CompFetchService.fetch(scan: scan, repository: repo, context: context, kicker: kicker)
    }

    /// True when the scan thinks it's fetching but the originating
    /// task can no longer exist — used to recover from app kills /
    /// view-model teardowns that left the persisted state at
    /// `.fetching` with nothing actually in flight.
    private static let fetchingStaleThreshold: TimeInterval = 90

    private func autoTriggerCompFetchIfNeeded() {
        guard scan.gradedCardIdentityId != nil else { return }
        // Either source landing means we have *something* to render;
        // only auto-trigger when we have nothing at all.
        guard pptSnapshot == nil && poketraceSnapshot == nil else { return }
        let state = scan.compFetchState.flatMap(CompFetchState.init(rawValue:))
        let stale: Bool = {
            guard state == .fetching else { return false }
            guard let last = scan.compFetchedAt else { return true }
            return Date().timeIntervalSince(last) > Self.fetchingStaleThreshold
        }()
        if state == nil || stale {
            retry()
        }
    }

}
