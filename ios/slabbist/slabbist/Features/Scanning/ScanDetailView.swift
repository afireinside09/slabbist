import SwiftUI
import SwiftData
import OSLog
import Supabase
import Auth

struct ScanDetailView: View {
    let scan: Scan
    @Environment(\.modelContext) private var context
    @Query private var snapshots: [GradedMarketSnapshot]

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
    }

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    if let snapshot = snapshots.first {
                        valueSection(snapshot: snapshot)
                        listingsSection(snapshot: snapshot)
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
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel(scan.grader.rawValue)
            Text(headerTitle)
                .slabTitle()
                .lineLimit(2)
            Text("Cert #\(scan.certNumber)")
                .font(SlabFont.mono(size: 12))
                .foregroundStyle(AppColor.muted)
        }
    }

    private var headerTitle: String {
        if let grade = scan.grade, !grade.isEmpty {
            return "\(scan.grader.rawValue) \(grade)"
        }
        return scan.grader.rawValue
    }

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
            title: "Pulling eBay sold listings…",
            detail: "This usually takes a couple of seconds.",
            showsProgress: true,
            cta: nil
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
                : "Once PSA confirms the cert, eBay comps will load automatically.",
            showsProgress: scan.status != .validationFailed,
            cta: nil
        )
    }

    private var noDataState: some View {
        emptyState(
            kicker: "No comps",
            symbol: "magnifyingglass",
            symbolTint: AppColor.muted,
            title: "No eBay sales found yet",
            detail: "This slab hasn't sold on eBay in the lookback window. Try again later, or this might just be a rarely-traded card.",
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

    // MARK: - Listings

    private func listingsSection(snapshot: GradedMarketSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Recent sales · \(snapshot.soldListings.count)")
            SlabCard {
                VStack(spacing: 0) {
                    let sorted = snapshot.soldListings.sorted(by: { $0.soldAt > $1.soldAt })
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, listing in
                        Link(destination: listing.url) {
                            listingRow(listing)
                        }
                        .buttonStyle(.plain)
                        if index < sorted.count - 1 {
                            SlabCardDivider()
                        }
                    }
                }
            }
        }
    }

    private func listingRow(_ l: SoldListingMirror) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(l.title)
                    .slabRowTitle()
                    .lineLimit(2)
                HStack(spacing: Spacing.s) {
                    Text(l.soldAt.formatted(date: .abbreviated, time: .omitted))
                        .font(SlabFont.mono(size: 11))
                        .foregroundStyle(AppColor.dim)
                    if l.isOutlier {
                        outlierChip(reason: l.outlierReason)
                    }
                }
            }
            Spacer(minLength: Spacing.m)
            Text(formatCents(l.soldPriceCents))
                .slabMetric()
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
    }

    private func outlierChip(reason: OutlierReason?) -> some View {
        Text(reason == .priceHigh ? "HIGH" : "LOW")
            .font(SlabFont.sans(size: 10, weight: .medium))
            .tracking(1.4)
            .foregroundStyle(AppColor.negative)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule().fill(AppColor.negative.opacity(0.12))
            )
    }

    private func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let fmt = NumberFormatter(); fmt.numberStyle = .currency; fmt.currencyCode = "USD"
        return fmt.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
}
