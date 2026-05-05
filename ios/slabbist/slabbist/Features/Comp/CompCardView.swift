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
                if !ladderTiers.isEmpty {
                    SlabCardDivider()
                    ladderRail
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                if showsCaveat {
                    SlabCardDivider()
                    caveatRow
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
                Text("\(snapshot.gradingService) \(snapshot.grade) · PRICECHARTING")
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

    // MARK: - Grade ladder

    private struct Tier: Identifiable {
        let id: String
        let label: String
        let cents: Int64
        let isHeadline: Bool
    }

    /// Ordered tiers we render in the ladder rail when present. The headline
    /// tier (matching the snapshot's grader+grade) gets a gold border.
    private var ladderTiers: [Tier] {
        let entries: [(id: String, label: String, cents: Int64?, headlineKey: (service: String, grade: String)?)] = [
            ("loose",     "Raw",        snapshot.loosePriceCents,     nil),
            ("grade_7",   "7",          snapshot.grade7PriceCents,    nil),
            ("grade_8",   "8",          snapshot.grade8PriceCents,    nil),
            ("grade_9",   "9",          snapshot.grade9PriceCents,    nil),
            ("grade_9_5", "9.5",        snapshot.grade9_5PriceCents,  nil),
            ("psa_10",    "PSA 10",     snapshot.psa10PriceCents,     ("PSA", "10")),
            ("bgs_10",    "BGS 10",     snapshot.bgs10PriceCents,     ("BGS", "10")),
            ("cgc_10",    "CGC 10",     snapshot.cgc10PriceCents,     ("CGC", "10")),
            ("sgc_10",    "SGC 10",     snapshot.sgc10PriceCents,     ("SGC", "10")),
        ]
        return entries.compactMap { e in
            guard let cents = e.cents else { return nil }
            let isHeadline: Bool = {
                if let k = e.headlineKey {
                    return k.service == snapshot.gradingService && k.grade == snapshot.grade
                }
                return false
            }()
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

    // MARK: - Caveat (stale fallback)

    private var showsCaveat: Bool { snapshot.isStaleFallback }

    private var caveatRow: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColor.negative)
            Text("Cached — PriceCharting unavailable")
                .font(SlabFont.sans(size: 12, weight: .medium))
                .foregroundStyle(AppColor.negative)
            Spacer()
        }
    }

    // MARK: - Footer (PriceCharting deep link)

    @ViewBuilder
    private var footerRow: some View {
        if let url = snapshot.pricechartingURL {
            Link(destination: url) {
                HStack(spacing: Spacing.xxs) {
                    Text("View real listings on PriceCharting")
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
