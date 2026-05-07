import SwiftUI
import SwiftData

struct CompCardView: View {
    let snapshot: GradedMarketSnapshot

    var body: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: 0) {
                heroRow
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, Spacing.l)
                    .padding(.bottom, Spacing.md)
                if !sparklinePoints.isEmpty {
                    SlabCardDivider()
                    CompSparklineView(points: sparklinePoints)
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
    }

    // MARK: - Hero

    private var heroRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(headlineText)
                    .font(SlabFont.serif(size: 40))
                    .tracking(-1)
                    .foregroundStyle(AppColor.text)
                Text("\(snapshot.gradingService) \(snapshot.grade)")
                    .font(SlabFont.sans(size: 10, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(AppColor.dim)
            }
            Spacer()
        }
    }

    private var headlineText: String {
        guard let cents = snapshot.headlinePriceCents else { return "—" }
        return formatCents(cents)
    }

    // MARK: - Sparkline

    private var sparklinePoints: [PriceHistoryPoint] {
        snapshot.priceHistory.sorted { $0.ts < $1.ts }
    }

    // MARK: - Grade ladder

    private struct Tier: Identifiable {
        let id: String
        let label: String
        let cents: Int64
        let isHeadline: Bool
    }

    /// Ordered tiers in the ladder rail. The cell matching the snapshot's
    /// (gradingService, grade) gets a gold border.
    private var ladderTiers: [Tier] {
        let entries: [(id: String, label: String, cents: Int64?, headlineKey: (service: String, grade: String)?)] = [
            ("loose",    "Raw",     snapshot.loosePriceCents,     nil),
            ("psa_7",    "PSA 7",   snapshot.psa7PriceCents,      ("PSA", "7")),
            ("psa_8",    "PSA 8",   snapshot.psa8PriceCents,      ("PSA", "8")),
            ("psa_9",    "PSA 9",   snapshot.psa9PriceCents,      ("PSA", "9")),
            ("psa_9_5",  "PSA 9.5", snapshot.psa9_5PriceCents,    ("PSA", "9.5")),
            ("psa_10",   "PSA 10",  snapshot.psa10PriceCents,     ("PSA", "10")),
            ("bgs_10",   "BGS 10",  snapshot.bgs10PriceCents,     ("BGS", "10")),
            ("cgc_10",   "CGC 10",  snapshot.cgc10PriceCents,     ("CGC", "10")),
            ("sgc_10",   "SGC 10",  snapshot.sgc10PriceCents,     ("SGC", "10")),
        ]
        return entries.compactMap { e in
            guard let cents = e.cents else { return nil }
            let isHeadline = e.headlineKey.map {
                $0.service == snapshot.gradingService && $0.grade == snapshot.grade
            } ?? false
            return Tier(id: e.id, label: e.label, cents: cents, isHeadline: isHeadline)
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
            RoundedRectangle(cornerRadius: 8)
                .stroke(tier.isHeadline ? AppColor.gold : AppColor.dim.opacity(0.3),
                        lineWidth: tier.isHeadline ? 1.5 : 1)
        )
    }

    // MARK: - Caveat

    /// One of three states: stale fallback, headline tier missing for a
    /// supported (grader, grade), or unsupported (grader, grade) entirely.
    private var caveatMessage: String? {
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
            Image(systemName: snapshot.isStaleFallback ? "wifi.slash" : "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(snapshot.isStaleFallback ? AppColor.negative : AppColor.dim)
            Text(message)
                .font(SlabFont.sans(size: 12, weight: .medium))
                .foregroundStyle(snapshot.isStaleFallback ? AppColor.negative : AppColor.dim)
            Spacer()
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerRow: some View {
        if let url = snapshot.pptURL {
            Link(destination: url) {
                HStack(spacing: Spacing.xxs) {
                    Text("Powered by Pokemon Price Tracker · View card")
                        .font(SlabFont.sans(size: 12, weight: .medium))
                        .foregroundStyle(AppColor.gold)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColor.gold)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        } else {
            EmptyView()
        }
    }

    // MARK: - Formatters

    private func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        fmt.maximumFractionDigits = 2
        return fmt.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }

    private func formatCentsCompact(_ cents: Int64) -> String {
        let dollars = Int((Double(cents) / 100).rounded())
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        fmt.maximumFractionDigits = 0
        return fmt.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
}

#Preview("Full ladder · PSA 10") {
    let history: [PriceHistoryPoint] = (0..<10).map { i in
        let interval: TimeInterval = TimeInterval(-i * 86_400 * 18)
        let price: Int64 = Int64(18_500 - i * 200)
        return PriceHistoryPoint(ts: Date(timeIntervalSinceNow: interval), priceCents: price)
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let json = String(data: (try? encoder.encode(history)) ?? Data(), encoding: .utf8)
    let snap = GradedMarketSnapshot(
        identityId: UUID(), gradingService: "PSA", grade: "10",
        headlinePriceCents: 18500, loosePriceCents: 400,
        psa7PriceCents: 2400, psa8PriceCents: 3400, psa9PriceCents: 6800, psa9_5PriceCents: 11200, psa10PriceCents: 18500,
        bgs10PriceCents: 21500, cgc10PriceCents: 16800, sgc10PriceCents: 16500,
        pptTCGPlayerId: "243172",
        pptURL: URL(string: "https://www.pokemonpricetracker.com/card/charizard-base-set"),
        priceHistoryJSON: json,
        fetchedAt: Date(), cacheHit: false, isStaleFallback: false
    )
    return CompCardView(snapshot: snap).padding().background(Color.black)
}

#Preview("BGS 10 headline") {
    let snap = GradedMarketSnapshot(
        identityId: UUID(), gradingService: "BGS", grade: "10",
        headlinePriceCents: 21500, loosePriceCents: 400,
        psa7PriceCents: nil, psa8PriceCents: nil, psa9PriceCents: nil, psa9_5PriceCents: nil, psa10PriceCents: 18500,
        bgs10PriceCents: 21500, cgc10PriceCents: 16800, sgc10PriceCents: nil,
        pptTCGPlayerId: "243172",
        pptURL: URL(string: "https://www.pokemonpricetracker.com/card/charizard-base-set"),
        priceHistoryJSON: nil,
        fetchedAt: Date(), cacheHit: false, isStaleFallback: false
    )
    return CompCardView(snapshot: snap).padding().background(Color.black)
}

#Preview("Unsupported tier · TAG 10") {
    let snap = GradedMarketSnapshot(
        identityId: UUID(), gradingService: "TAG", grade: "10",
        headlinePriceCents: nil, loosePriceCents: 400,
        psa7PriceCents: nil, psa8PriceCents: nil, psa9PriceCents: nil, psa9_5PriceCents: nil, psa10PriceCents: 18500,
        bgs10PriceCents: nil, cgc10PriceCents: nil, sgc10PriceCents: nil,
        pptTCGPlayerId: "243172",
        pptURL: URL(string: "https://www.pokemonpricetracker.com/card/charizard-base-set"),
        priceHistoryJSON: nil,
        fetchedAt: Date(), cacheHit: false, isStaleFallback: false
    )
    return CompCardView(snapshot: snap).padding().background(Color.black)
}
