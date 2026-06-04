import SwiftUI
import SwiftData

/// Single-source comp card. Poketrace is the sole pricing source since the
/// PPT removal. The hero number comes from
/// `scan.reconciledHeadlinePriceCents` (set by the server); the ladder reads
/// `snapshot.ptTierPricesCents`; aggregates read the `pt*` fields; the
/// sparkline reads `snapshot.priceHistory`.
///
/// Below the aggregates, a `CompSoldListingsView` surfaces individual eBay
/// sold comps when the server returned them (Scale plan). It degrades
/// gracefully to an empty-state note when sold-listings data is unavailable.
struct CompCardView: View {
    let scan: Scan
    let snapshot: GradedMarketSnapshot?

    /// Sorted history: computed once per snapshot identity so a body
    /// re-eval doesn't re-sort on every pass.
    @State private var sortedHistory: [PriceHistoryPoint] = []

    var body: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: 0) {
                heroRow
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, Spacing.l)
                    .padding(.bottom, Spacing.md)
                SlabCardDivider()
                aggregatesRow
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.md)
                if !sortedHistory.isEmpty {
                    SlabCardDivider()
                    CompSparklineView(points: sortedHistory)
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                if !ladderTiers.isEmpty {
                    SlabCardDivider()
                    ladderRail
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                // Sold (eBay) listings are a Poketrace Scale-plan feature; off
                // that plan the array is always empty, so hide the section
                // entirely rather than show a permanently-empty placeholder.
                if let soldListings = snapshot?.soldListings, !soldListings.isEmpty {
                    SlabCardDivider()
                    CompSoldListingsView(
                        soldListings: soldListings,
                        marketplaceURL: snapshot?.marketplaceURL
                    )
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.md)
                }
                SlabCardDivider()
                footerRow
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.md)
            }
        }
        .onAppear { refreshSortedHistory() }
        .onChange(of: snapshotCacheKey) { _, _ in refreshSortedHistory() }
    }

    /// Stable cache key for the snapshot, used to invalidate the sorted
    /// history when a refetch produces a new model row.
    private var snapshotCacheKey: String {
        guard let s = snapshot else { return "" }
        return "\(s.persistentModelID.hashValue)|\(s.fetchedAt.timeIntervalSince1970)"
    }

    private func refreshSortedHistory() {
        sortedHistory = (snapshot?.priceHistory ?? []).sorted { $0.ts < $1.ts }
    }

    // MARK: - Hero

    /// Three discrete display states for the hero number. `.confident` is
    /// the Poketrace headline. `.estimated` walks an *intra-grader*
    /// descending ladder when the headline tier has no data. `.unavailable`
    /// fires when neither reconciled nor any same-grader ladder tier exists.
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
        .animation(.easeInOut(duration: 0.25), value: heroValue)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: heroAccessibilityLabel))
    }

    private var heroNumber: some View {
        Text(heroText)
            .font(SlabFont.serif(size: 40))
            .tracking(-1)
            .foregroundStyle(heroColor)
            .contentTransition(.numericText())
    }

    private var heroText: String {
        switch heroValue {
        case .confident(let cents):    return formatCents(cents)
        case .estimated(let cents, _): return "~\(formatCents(cents))"
        case .unavailable:             return "—"
        }
    }

    private var heroColor: Color {
        switch heroValue {
        case .confident:  return AppColor.text
        case .estimated:  return AppColor.muted
        case .unavailable: return AppColor.dim
        }
    }

    private var heroCaption: String {
        switch heroValue {
        case .confident:
            return poketraceCaption
        case .estimated(_, let source):
            let graderTier = "\(scan.grader.rawValue) \(scan.grade ?? "")"
                .trimmingCharacters(in: .whitespaces)
            return "ESTIMATE FROM \(source.uppercased()) · NO \(graderTier.uppercased()) SALES YET"
        case .unavailable:
            return "NO PRICE DATA"
        }
    }

    private var heroAccessibilityLabel: String {
        switch heroValue {
        case .confident(let cents):
            return "\(formatCents(cents)). \(poketraceCaption.capitalized)."
        case .estimated(let cents, let source):
            let graderTier = "\(scan.grader.rawValue) \(scan.grade ?? "")"
                .trimmingCharacters(in: .whitespaces)
            return "Approximately \(formatCents(cents)). Estimate from \(source). No \(graderTier) sales yet."
        case .unavailable:
            return "No price data."
        }
    }

    /// Caption beneath the hero, reflecting the Poketrace source. Includes
    /// sale count when available so the operator sees how many sales back the
    /// estimate. `scan.reconciledSource` is always "poketrace" on new rows;
    /// kept for forward compatibility with the field.
    private var poketraceCaption: String {
        let graderTier = "\(scan.grader.rawValue) \(scan.grade ?? "")".trimmingCharacters(in: .whitespaces)
        let suffix = graderTier.isEmpty ? "" : " · \(graderTier)"
        if let n = snapshot?.ptSaleCount {
            return "Poketrace · n=\(n)\(suffix)"
        }
        return "Poketrace\(suffix)"
    }

    // MARK: - Adjacency walk (intra-grader fallback)

    /// Walk an intra-grader descending ladder to find the nearest tier with
    /// a value when the scan's own (grader, grade) cell is empty.
    ///
    /// **Why intra-grader only?** Cross-grader walks pick "first tier with
    /// data" rather than "nearest market value" — graders trade at very
    /// different premiums (BGS Black Label ≫ PSA 10 ≫ CGC 10). Showing a
    /// PSA 10 estimate on a BGS 10 scan would lowball the dealer's offer.
    func nearestLadderTier() -> (cents: Int64, label: String)? {
        let service = scan.grader.rawValue
        let grade   = scan.grade ?? ""
        let candidates = adjacencyCandidates(service: service, grade: grade)
        let byId = Dictionary(ladderTiers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in candidates {
            if let tier = byId[id] { return (tier.cents, tier.label) }
        }
        return nil
    }

    private func adjacencyCandidates(service: String, grade: String) -> [String] {
        switch (service, grade) {
        case ("PSA", "10"):  return ["psa_9_5", "psa_9", "psa_8", "psa_7"]
        case ("PSA", "9.5"): return ["psa_9", "psa_8", "psa_7"]
        case ("PSA", "9"):   return ["psa_9_5", "psa_8", "psa_7"]
        case ("PSA", "8"):   return ["psa_9", "psa_9_5", "psa_7"]
        case ("PSA", "7"):   return ["psa_8", "psa_9"]
        case ("BGS", _), ("CGC", _), ("SGC", _), ("TAG", _): return []
        default: return []
        }
    }

    // MARK: - Aggregates row

    /// Side-by-side aggregate cells: avg price, sale count + trend, range,
    /// confidence. A single source strip replaces the old two-source strip.
    private var aggregatesRow: some View {
        HStack(alignment: .top, spacing: Spacing.l) {
            aggregateCell(
                title: "Avg",
                value: snapshot?.ptAvgCents.map { formatCents($0) } ?? "—",
                highlight: snapshot?.ptConfidence
            )
            Rectangle()
                .fill(AppColor.hairline)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            aggregateCell(
                title: "Range",
                value: priceRangeText
            )
            Rectangle()
                .fill(AppColor.hairline)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            aggregateCell(
                title: "Sales",
                value: salesAndTrendText
            )
        }
        .frame(minHeight: 44)
    }

    private var priceRangeText: String {
        guard let s = snapshot, let lo = s.ptLowCents, let hi = s.ptHighCents else { return "—" }
        return "\(formatCentsCompact(lo))–\(formatCentsCompact(hi))"
    }

    private var salesAndTrendText: String {
        guard let s = snapshot else { return "—" }
        var parts: [String] = []
        if let n = s.ptSaleCount { parts.append("n=\(n)") }
        if let trend = s.ptTrend  { parts.append(trendChevron(trend)) }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    private func trendChevron(_ trend: String) -> String {
        switch trend {
        case "up":   return "▲"
        case "down": return "▼"
        default:     return "–"
        }
    }

    private func aggregateCell(title: String, value: String, highlight: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(SlabFont.sans(size: 10, weight: .medium))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.dim)
            Text(value)
                .font(SlabFont.mono(size: 14, weight: .semibold))
                .foregroundStyle(confidenceColor(highlight))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func confidenceColor(_ confidence: String?) -> Color {
        switch confidence {
        case "high":   return AppColor.text
        case "medium": return AppColor.text.opacity(0.85)
        case "low":    return AppColor.muted
        default:       return AppColor.text
        }
    }

    // MARK: - Grade ladder

    private struct Tier: Identifiable {
        let id: String
        let label: String
        let cents: Int64
        let isHeadline: Bool
    }

    /// Canonical ladder layout; matches the server-side snake_case tier ids
    /// from `ptTierPricesCents`.
    private static let ladderLayout: [(id: String, label: String, headlineKey: (service: String, grade: String)?)] = [
        ("loose",   "Raw",     nil),
        ("psa_10",  "PSA 10",  ("PSA", "10")),
        ("psa_9_5", "PSA 9.5", ("PSA", "9.5")),
        ("psa_9",   "PSA 9",   ("PSA", "9")),
        ("psa_8",   "PSA 8",   ("PSA", "8")),
        ("psa_7",   "PSA 7",   ("PSA", "7")),
        ("cgc_10",  "CGC 10",  ("CGC", "10")),
        ("bgs_10",  "BGS 10",  ("BGS", "10")),
        ("sgc_10",  "SGC 10",  ("SGC", "10")),
    ]

    private var ladderTiers: [Tier] {
        guard let snapshot else { return [] }
        let prices = snapshot.ptTierPricesCents
        return Self.ladderLayout.compactMap { layout in
            guard let cents = prices[layout.id] else { return nil }
            let isHeadline = layout.headlineKey.map {
                $0.service == snapshot.gradingService && $0.grade == snapshot.grade
            } ?? false
            return Tier(id: layout.id, label: layout.label, cents: cents, isHeadline: isHeadline)
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

    // MARK: - Footer

    @ViewBuilder
    private var footerRow: some View {
        HStack {
            Text("Comp data from Poketrace")
                .font(SlabFont.sans(size: 12, weight: .medium))
                .foregroundStyle(AppColor.dim)
            Spacer()
        }
    }

    // MARK: - Formatters

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

// MARK: - Previews

#Preview("Poketrace · PSA 10 · with sold listings") {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let history: [PriceHistoryPoint] = (0..<10).map { (i: Int) -> PriceHistoryPoint in
        let secondsAgo = TimeInterval(-i) * 86_400 * 18
        let cents = Int64(18_500 - i * 200)
        return PriceHistoryPoint(ts: Date(timeIntervalSinceNow: secondsAgo), priceCents: cents)
    }
    let historyJSON = String(data: (try? encoder.encode(history)) ?? Data(), encoding: .utf8)

    let listings: [SoldListing] = [
        SoldListing(
            sourceListingId: "e1",
            title: "Charizard Base Set PSA 10",
            priceCents: 18_200,
            soldAt: Date(timeIntervalSinceNow: -86_400 * 2),
            grader: "PSA", grade: "10", condition: "Graded",
            url: URL(string: "https://www.ebay.com/itm/123456789"),
            anomalyFlag: nil
        ),
        SoldListing(
            sourceListingId: "e2",
            title: "Charizard Base Set PSA 10 Vintage",
            priceCents: 19_800,
            soldAt: Date(timeIntervalSinceNow: -86_400 * 5),
            grader: "PSA", grade: "10", condition: "Graded",
            url: URL(string: "https://www.ebay.com/itm/987654321"),
            anomalyFlag: "outlier_high"
        ),
    ]
    let listingsJSON = String(data: (try? encoder.encode(listings)) ?? Data(), encoding: .utf8)

    let tierPrices: [String: Int64] = [
        "loose": 400, "psa_7": 2_400, "psa_8": 3_400, "psa_9": 6_800,
        "psa_9_5": 11_200, "psa_10": 18_500, "bgs_10": 21_500,
        "cgc_10": 16_800, "sgc_10": 16_500,
    ]
    let tierJSON = String(
        data: (try? JSONEncoder().encode(tierPrices)) ?? Data(),
        encoding: .utf8
    )

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

    let snapshot = GradedMarketSnapshot(
        identityId: identityId,
        gradingService: "PSA",
        grade: "10",
        source: GradedMarketSnapshot.sourcePoketrace,
        headlinePriceCents: 18_750,
        ptAvgCents: 18_750,
        ptLowCents: 17_500,
        ptHighCents: 21_000,
        ptTrend: "up",
        ptConfidence: "high",
        ptSaleCount: 14,
        ptTierPricesJSON: tierJSON,
        priceHistoryJSON: historyJSON,
        marketplaceURL: URL(string: "https://www.ebay.com/sch/i.html?_nkw=charizard+base+set+psa+10"),
        soldListingsJSON: listingsJSON,
        fetchedAt: Date(),
        cacheHit: false
    )
    return CompCardView(scan: scan, snapshot: snapshot)
        .padding().background(AppColor.ink)
}

#Preview("Poketrace · PSA 9 · no sold listings") {
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

    let tierPrices: [String: Int64] = [
        "loose": 350, "psa_7": 1_800, "psa_8": 2_900, "psa_9": 6_800,
    ]
    let tierJSON = String(
        data: (try? JSONEncoder().encode(tierPrices)) ?? Data(),
        encoding: .utf8
    )

    let snapshot = GradedMarketSnapshot(
        identityId: identityId,
        gradingService: "PSA",
        grade: "9",
        source: GradedMarketSnapshot.sourcePoketrace,
        headlinePriceCents: 6_800,
        ptAvgCents: 6_800,
        ptLowCents: 6_100,
        ptHighCents: 7_400,
        ptTrend: "stable",
        ptConfidence: "medium",
        ptSaleCount: 6,
        ptTierPricesJSON: tierJSON,
        priceHistoryJSON: nil,
        marketplaceURL: URL(string: "https://www.ebay.com/sch/i.html?_nkw=charizard+base+set+psa+9"),
        soldListingsJSON: nil,
        fetchedAt: Date(),
        cacheHit: false
    )
    return CompCardView(scan: scan, snapshot: snapshot)
        .padding().background(AppColor.ink)
}

#Preview("No snapshot") {
    let identityId = UUID()
    let scan = Scan(
        id: UUID(), storeId: UUID(), lotId: UUID(), userId: UUID(),
        grader: .PSA, certNumber: "00000000",
        grade: "10",
        gradedCardIdentityId: identityId,
        status: .validated,
        createdAt: Date(), updatedAt: Date()
    )
    return CompCardView(scan: scan, snapshot: nil)
        .padding().background(AppColor.ink)
}
