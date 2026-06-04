import SwiftUI

/// Sold eBay comps section in the comp card. Shows up to ~10 individual
/// sold listings from Poketrace's `/cards/{id}/listings` endpoint.
///
/// **Degrade path:** When `soldListings` is empty (off the Poketrace Scale
/// plan, or the card has no recent sales), renders a compact "No individual
/// sales available" note — no spinner, no CTA.
///
/// **Layout:** Header kicker + count, up to 10 rows (title, grade chip,
/// price, sold date), anomaly annotation, footer deep-link to all sales.
struct CompSoldListingsView: View {
    let soldListings: [SoldListing]
    let marketplaceURL: URL?

    // Display at most 10 rows — beyond that the user should tap "View all".
    private static let displayLimit = 10

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            header
            if soldListings.isEmpty {
                emptyState
            } else {
                listingRows
                if let url = marketplaceURL {
                    viewAllFooter(url: url)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Recent eBay sales")
                .font(SlabFont.sans(size: 10, weight: .medium))
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.dim)
            if !soldListings.isEmpty {
                Text("(\(soldListings.count))")
                    .font(SlabFont.mono(size: 10, weight: .regular))
                    .foregroundStyle(AppColor.dim)
            }
            Spacer()
        }
    }

    // MARK: - Empty state

    /// Compact single-line note; shown off the Scale plan or for cards with
    /// no recent eBay sales. No spinner: the data simply isn't available.
    private var emptyState: some View {
        Text("No individual sales available")
            .font(SlabFont.sans(size: 12, weight: .medium))
            .foregroundStyle(AppColor.dim)
            .accessibilityLabel("No individual sales available")
    }

    // MARK: - Listing rows

    private var listingRows: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(soldListings.prefix(Self.displayLimit)) { listing in
                listingRow(listing)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(listingAccessibilityLabel(listing))
            }
        }
    }

    @ViewBuilder
    private func listingRow(_ listing: SoldListing) -> some View {
        Group {
            if let url = listing.url {
                Link(destination: url) { listingRowContent(listing) }
                    .buttonStyle(.plain)
            } else {
                listingRowContent(listing)
            }
        }
    }

    private func listingRowContent(_ listing: SoldListing) -> some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    // Grade chip
                    if let grader = listing.grader, let grade = listing.grade {
                        gradeChip(grader: grader, grade: grade)
                    }
                    // Anomaly annotation
                    if listing.anomalyFlag != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(SlabFont.sans(size: 10, weight: .medium))
                            .foregroundStyle(AppColor.negative)
                            .accessibilityLabel("Flagged sale")
                    }
                }
                Text(listing.title ?? "Untitled listing")
                    .font(SlabFont.sans(size: 12, weight: .medium))
                    .foregroundStyle(listing.url != nil ? AppColor.gold : AppColor.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: Spacing.s)
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                if let cents = listing.priceCents {
                    Text(formatCentsCompact(cents))
                        .font(SlabFont.mono(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.text)
                } else {
                    Text("—")
                        .font(SlabFont.mono(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.dim)
                }
                Text(relativeDateString(listing.soldAt))
                    .font(SlabFont.mono(size: 10, weight: .regular))
                    .foregroundStyle(AppColor.dim)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func gradeChip(grader: String, grade: String) -> some View {
        Text("\(grader) \(grade)")
            .font(SlabFont.sans(size: 9, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(AppColor.text)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Radius.s - 2, style: .continuous)
                    .fill(AppColor.elev2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.s - 2, style: .continuous)
                    .stroke(AppColor.hairline, lineWidth: 1)
            )
    }

    // MARK: - Footer deep-link

    private func viewAllFooter(url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: Spacing.xxs) {
                Text("View all sold on eBay")
                    .font(SlabFont.sans(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.gold)
                Image(systemName: "arrow.up.right")
                    .font(SlabFont.sans(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.gold)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, Spacing.xxs)
    }

    // MARK: - Helpers

    private static let usdCompactFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f
    }()

    private func formatCentsCompact(_ cents: Int64) -> String {
        let dollars = Int((Double(cents) / 100).rounded())
        return Self.usdCompactFormatter.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }

    /// Compact relative date: "2d ago", "3w ago", "5mo ago".
    /// Falls back to abbreviated formatted date for dates > ~1 year.
    private func relativeDateString(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        guard interval >= 0 else { return date.formatted(date: .abbreviated, time: .omitted) }
        let days = Int(interval / 86_400)
        switch days {
        case 0:         return "today"
        case 1:         return "1d ago"
        case 2..<14:    return "\(days)d ago"
        case 14..<30:   return "\(days / 7)w ago"
        case 30..<365:  return "\(days / 30)mo ago"
        default:        return date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private func listingAccessibilityLabel(_ listing: SoldListing) -> String {
        let gradeStr = [listing.grader, listing.grade].compactMap { $0 }.joined(separator: " ")
        let priceStr = listing.priceCents.map { formatCentsCompact($0) } ?? "price unknown"
        let titleStr = listing.title ?? "untitled listing"
        let dateStr = relativeDateString(listing.soldAt)
        let flagStr = listing.anomalyFlag != nil ? ", flagged as anomaly" : ""
        return "\(gradeStr.isEmpty ? "" : gradeStr + ", ")\(titleStr), \(priceStr), \(dateStr)\(flagStr)"
    }
}

// MARK: - Previews

#Preview("With listings") {
    let listings: [SoldListing] = [
        SoldListing(
            sourceListingId: "e1",
            title: "Charizard Base Set PSA 10 Gem Mint",
            priceCents: 18_200,
            soldAt: Date(timeIntervalSinceNow: -86_400 * 2),
            grader: "PSA", grade: "10",
            condition: "Graded",
            url: URL(string: "https://www.ebay.com/itm/111"),
            anomalyFlag: nil
        ),
        SoldListing(
            sourceListingId: "e2",
            title: "Pokemon Charizard WOTC PSA 10",
            priceCents: 19_800,
            soldAt: Date(timeIntervalSinceNow: -86_400 * 5),
            grader: "PSA", grade: "10",
            condition: "Graded",
            url: URL(string: "https://www.ebay.com/itm/222"),
            anomalyFlag: "outlier_high"
        ),
        SoldListing(
            sourceListingId: "e3",
            title: "Charizard 4/102 Base Unlimited PSA 10",
            priceCents: 17_500,
            soldAt: Date(timeIntervalSinceNow: -86_400 * 12),
            grader: "PSA", grade: "10",
            condition: "Graded",
            url: nil,
            anomalyFlag: nil
        ),
    ]
    CompSoldListingsView(
        soldListings: listings,
        marketplaceURL: URL(string: "https://www.ebay.com/sch/i.html?_nkw=charizard+psa+10")
    )
    .padding()
    .background(AppColor.ink)
}

#Preview("Empty — non-Scale plan degrade") {
    CompSoldListingsView(soldListings: [], marketplaceURL: nil)
        .padding()
        .background(AppColor.ink)
}
