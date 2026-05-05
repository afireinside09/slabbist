import SwiftUI
import SwiftData
import OSLog
import Supabase
import Auth

struct ScanDetailView: View {
    let scan: Scan
    @Environment(\.modelContext) private var context
    @Query private var snapshots: [GradedMarketSnapshot]
    @Query private var identities: [GradedCardIdentity]

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

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    if let snapshot = snapshots.first {
                        valueSection(snapshot: snapshot)
                    } else {
                        fallbackContent
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

    private func valueSection(snapshot: GradedMarketSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Market value")
            CompCardView(snapshot: snapshot)
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
            title: "Fetching PriceCharting comp…",
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
            title: "PriceCharting has no comp for this slab",
            detail: "Either we couldn't find this card on PriceCharting, or there's no published price for this tier yet. Try retrying later.",
            showsProgress: false,
            cta: ("Retry comp fetch", retry)
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
            cta: ("Retry comp fetch", retry)
        )
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
        cta: (label: String, action: () -> Void)?
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
        }
    }

    private func retry() {
        let baseURL = AppEnvironment.supabaseURL.appendingPathComponent("/functions/v1")
        let repo = CompRepository(
            baseURL: baseURL,
            authTokenProvider: { try? await AppSupabase.shared.client.auth.session.accessToken }
        )
        CompFetchService.fetch(scan: scan, repository: repo, context: context)
    }

    /// True when the scan thinks it's fetching but the originating
    /// task can no longer exist — used to recover from app kills /
    /// view-model teardowns that left the persisted state at
    /// `.fetching` with nothing actually in flight.
    private static let fetchingStaleThreshold: TimeInterval = 90

    private func autoTriggerCompFetchIfNeeded() {
        guard scan.gradedCardIdentityId != nil else { return }
        guard snapshots.first == nil else { return }
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
