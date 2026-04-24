import SwiftUI
import SwiftData

struct ScanDetailView: View {
    let scan: Scan
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
                } else {
                    ProgressView("Fetching comps…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .navigationTitle("\(scan.grader.rawValue) \(scan.grade ?? "")")
    }

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
