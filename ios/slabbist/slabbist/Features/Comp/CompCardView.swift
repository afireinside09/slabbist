import SwiftUI
import SwiftData

struct CompCardView: View {
    let snapshot: GradedMarketSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline
            breakdown
            if snapshot.sampleCount < 10 || snapshot.isStaleFallback {
                lowConfidenceChip
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.thinMaterial))
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(formatCents(snapshot.trimmedMeanPriceCents))
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Spacer()
            ConfidenceMeter(value: snapshot.confidence)
                .frame(width: 80, height: 14)
        }
    }

    private var breakdown: some View {
        HStack(spacing: 16) {
            statCell("Mean",     snapshot.meanPriceCents)
            statCell("Trimmed",  snapshot.trimmedMeanPriceCents)
            statCell("Median",   snapshot.medianPriceCents)
            statCell("Low",      snapshot.lowPriceCents)
            statCell("High",     snapshot.highPriceCents)
        }
        .font(.footnote)
    }

    private var lowConfidenceChip: some View {
        Text(snapshot.isStaleFallback
             ? "Cached — live data unavailable"
             : "Low confidence — \(snapshot.sampleCount) comps")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.orange.opacity(0.2)))
            .foregroundStyle(.orange)
    }

    private func statCell(_ label: String, _ cents: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text(formatCents(cents)).fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        fmt.maximumFractionDigits = 2
        return fmt.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
}

struct ConfidenceMeter: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7).fill(.quaternary)
                RoundedRectangle(cornerRadius: 7)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, value))))
            }
        }
    }
    private var color: Color {
        if value >= 0.75 { return .green }
        if value >= 0.4  { return .yellow }
        return .orange
    }
}
