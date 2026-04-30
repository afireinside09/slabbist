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
                SlabCardDivider()
                StatStrip(items: rangeItems)
                    .padding(.horizontal, Spacing.l)
                if showsCaveat {
                    SlabCardDivider()
                    caveatRow
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                metaRow
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, Spacing.md)
                    .padding(.top, Spacing.s)
            }
        }
    }

    // MARK: - Hero

    private var heroRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(formatCents(snapshot.trimmedMeanPriceCents))
                    .font(SlabFont.serif(size: 40))
                    .tracking(-1)
                    .foregroundStyle(AppColor.text)
                Text("TRIMMED MEAN · \(snapshot.sampleCount) COMPS")
                    .font(SlabFont.sans(size: 10, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(AppColor.dim)
            }
            Spacer()
            confidenceChip
        }
    }

    private var confidenceChip: some View {
        Text("\(Int((snapshot.confidence * 100).rounded()))%")
            .font(SlabFont.mono(size: 12, weight: .medium))
            .foregroundStyle(confidenceTint)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
            .overlay(
                Capsule().stroke(confidenceTint.opacity(0.4), lineWidth: 1)
            )
    }

    private var confidenceTint: Color {
        if snapshot.confidence >= 0.75 { return AppColor.positive }
        if snapshot.confidence >= 0.40 { return AppColor.gold }
        return AppColor.negative
    }

    // MARK: - Range strip

    private var rangeItems: [StatStrip.Item] {
        [
            .init(label: "Low",    value: formatCentsCompact(snapshot.lowPriceCents)),
            .init(label: "Median", value: formatCentsCompact(snapshot.medianPriceCents)),
            .init(label: "High",   value: formatCentsCompact(snapshot.highPriceCents)),
        ]
    }

    // MARK: - Caveat (low-confidence / stale)

    private var showsCaveat: Bool {
        snapshot.isStaleFallback || snapshot.sampleCount < 10
    }

    private var caveatRow: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: snapshot.isStaleFallback ? "wifi.slash" : "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColor.negative)
            Text(snapshot.isStaleFallback
                 ? "Cached — live data unavailable"
                 : "Low confidence — \(snapshot.sampleCount) comps")
                .font(SlabFont.sans(size: 12, weight: .medium))
                .foregroundStyle(AppColor.negative)
            Spacer()
        }
    }

    // MARK: - Meta footer

    private var metaRow: some View {
        HStack {
            Text("Mean \(formatCentsCompact(snapshot.meanPriceCents))")
                .font(SlabFont.mono(size: 11))
                .foregroundStyle(AppColor.muted)
            Spacer()
            Text("\(snapshot.sampleWindowDays)D WINDOW")
                .font(SlabFont.sans(size: 10, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(AppColor.dim)
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

    /// Compact form (no cents) for the dense stat strip — keeps three cells
    /// readable at phone widths.
    private func formatCentsCompact(_ cents: Int64) -> String {
        let dollars = Int((Double(cents) / 100).rounded())
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        fmt.maximumFractionDigits = 0
        return fmt.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
}
