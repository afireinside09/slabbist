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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let snapshot = snapshots.first {
                    CompCardView(snapshot: snapshot)
                    listingsSection(snapshot: snapshot)
                    if let attemptedAt = scan.compFetchedAt {
                        Text("Last refreshed \(attemptedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    refreshButton
                } else {
                    fallbackContent
                }
            }
            .padding()
        }
        .navigationTitle("\(scan.grader.rawValue) \(scan.grade ?? "")")
    }

    // MARK: - State machine

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
        VStack(spacing: 12) {
            ProgressView()
            Text("Fetching eBay sold listings…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
    }

    private var certNotResolvedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.diamond")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(scan.status == .validationFailed ? "Cert lookup failed"
                                                  : "Validating cert…")
                .font(.headline)
            Text(scan.status == .validationFailed
                 ? "PSA didn't recognize cert \(scan.certNumber). Delete this slab and re-scan if the digits look wrong."
                 : "Once PSA confirms the cert, eBay comps will load automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
        .padding(.horizontal)
    }

    private var noDataState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No eBay sales found yet")
                .font(.headline)
            Text("This slab hasn't sold on eBay in the lookback window. Try again later, or this might just be a rarely-traded card.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            refreshButton
            if let at = scan.compFetchedAt {
                Text("Checked \(at.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
        .padding(.horizontal)
    }

    private var failedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Comp fetch failed")
                .font(.headline)
            Text(scan.compFetchError ?? "Unknown error")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            refreshButton
            if let at = scan.compFetchedAt {
                Text("Last attempt \(at.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
        .padding(.horizontal)
    }

    private var refreshButton: some View {
        Button(action: retry) {
            Label("Retry comp fetch", systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
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
        DisclosureGroup("View all \(snapshot.soldListings.count) sold listings") {
            VStack(spacing: 8) {
                ForEach(snapshot.soldListings.sorted(by: { $0.soldAt > $1.soldAt })) { listing in
                    Link(destination: listing.url) { listingRow(listing) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
    }

    private func listingRow(_ l: SoldListingMirror) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l.title).lineLimit(2).font(.subheadline)
                Spacer()
                Text(formatCents(l.soldPriceCents)).font(.subheadline.monospacedDigit())
            }
            HStack(spacing: 8) {
                Text(l.soldAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
                if l.isOutlier {
                    Text(l.outlierReason == .priceHigh ? "High outlier" : "Low outlier")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let fmt = NumberFormatter(); fmt.numberStyle = .currency; fmt.currencyCode = "USD"
        return fmt.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
}
