import Charts
import SwiftUI

/// Detail screen reached by tapping a Grade Gains row. Shows the card
/// hero, a raw → PSA 10 → fee → profit breakdown, and the RAW card's
/// 90-day market-price history. Graded (PSA 10) history is deferred to
/// v2 — this screen only charts the raw side. Mirrors `MoverDetailView`'s
/// hero + chart treatment.
struct GradeGainDetailView: View {
    private let gain: GradeGainDTO
    private let feeCents: Int

    @State private var historyState: HistoryState = .idle

    private let repository = SupabaseMoversRepository()

    init(gain: GradeGainDTO, feeCents: Int) {
        self.gain = gain
        self.feeCents = feeCents
    }

    private enum HistoryState {
        case idle
        case loading
        case loaded([PriceHistoryDTO])
        case error(String)
    }

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    hero
                    breakdownCard
                    historyCard
                    TCGPlayerLinkButton(productId: gain.productId, subId: "gradegain")
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .navigationTitle(gain.productName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadHistory() }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            heroImage
            VStack(alignment: .leading, spacing: Spacing.xs) {
                KickerLabel(gain.subTypeName)
                Text(gain.productName).slabTitle()
                if let set = gain.groupName, !set.isEmpty {
                    Text(set)
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.muted)
                }
            }
        }
    }

    @ViewBuilder
    private var heroImage: some View {
        if let urlString = gain.imageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 320)
                case .failure:
                    imagePlaceholder
                case .empty:
                    imagePlaceholder.redacted(reason: .placeholder)
                @unknown default:
                    imagePlaceholder
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .fill(AppColor.elev)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .stroke(AppColor.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
            .fill(AppColor.elev)
            .overlay(
                Image(systemName: "photo")
                    .font(SlabFont.sans(size: 28, weight: .regular))
                    .foregroundStyle(AppColor.dim)
            )
            .frame(height: 240)
    }

    // MARK: - Profit breakdown card

    private var breakdownCard: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HeroValueBlock(
                    kicker: "Profit after fee",
                    cents: Int64(gain.profitCents(feeCents: feeCents)),
                    delta: nil,
                    deltaTint: .positive,
                    size: 54
                )

                SlabCardDivider()

                VStack(spacing: Spacing.m) {
                    breakdownRow(label: "Raw", value: GradeGainFormat.money(gain.rawPriceCents), tint: AppColor.text)
                    breakdownRow(label: "PSA 10", value: GradeGainFormat.money(gain.psa10PriceCents), tint: AppColor.text)
                    breakdownRow(label: "Grading fee", value: "−\(GradeGainFormat.money(feeCents))", tint: AppColor.muted)
                    SlabCardDivider()
                    breakdownRow(
                        label: "Profit",
                        value: GradeGainFormat.money(gain.profitCents(feeCents: feeCents)),
                        tint: AppColor.gold,
                        emphasized: true
                    )
                }
            }
            .padding(Spacing.l)
        }
    }

    private func breakdownRow(
        label: String,
        value: String,
        tint: Color,
        emphasized: Bool = false
    ) -> some View {
        HStack {
            Text(label)
                .font(SlabFont.sans(size: emphasized ? 14 : 13, weight: emphasized ? .semibold : .regular))
                .foregroundStyle(emphasized ? AppColor.text : AppColor.muted)
            Spacer()
            Text(value)
                .font(SlabFont.mono(size: emphasized ? 16 : 13, weight: .semibold))
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    // MARK: - History chart

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                KickerLabel("Raw · 90-day market price")
                Spacer()
                if case let .loaded(points) = historyState, points.count >= 2 {
                    Text("\(points.count) pts")
                        .font(SlabFont.mono(size: 11))
                        .foregroundStyle(AppColor.dim)
                }
            }
            SlabCard {
                historyBody
                    .frame(height: 220)
                    .padding(Spacing.l)
            }
        }
    }

    @ViewBuilder
    private var historyBody: some View {
        switch historyState {
        case .idle, .loading:
            chartSkeleton
        case .loaded(let points):
            if points.isEmpty {
                chartEmpty(message: "No price history in the last 90 days.")
            } else if points.count == 1 {
                chartEmpty(message: "Only one snapshot so far. Chart appears once a second sync lands.")
            } else {
                chart(points: points)
            }
        case .error(let message):
            chartEmpty(message: message, isError: true)
        }
    }

    private func chart(points: [PriceHistoryDTO]) -> some View {
        Chart(points, id: \.capturedAt) { point in
            LineMark(
                x: .value("Date", point.capturedAt),
                y: .value("Market", point.marketPrice)
            )
            .foregroundStyle(AppColor.gold)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            .interpolationMethod(.monotone)

            AreaMark(
                x: .value("Date", point.capturedAt),
                y: .value("Market", point.marketPrice)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [AppColor.gold.opacity(0.28), AppColor.gold.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(AppColor.hairline)
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(MoversFormat.price(price))
                            .font(SlabFont.mono(size: 10))
                            .foregroundStyle(AppColor.dim)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(AppColor.hairline)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Self.day.string(from: date))
                            .font(SlabFont.mono(size: 10))
                            .foregroundStyle(AppColor.dim)
                    }
                }
            }
        }
        .accessibilityLabel("Raw price history")
        .accessibilityValue(accessibilitySummary(points: points))
    }

    private var chartSkeleton: some View {
        RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
            .fill(AppColor.elev2)
            .opacity(0.55)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chartEmpty(message: String, isError: Bool = false) -> some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: isError ? "exclamationmark.triangle" : "chart.line.flattrend.xyaxis")
                .font(SlabFont.sans(size: 24, weight: .regular))
                .foregroundStyle(isError ? AppColor.negative : AppColor.gold.opacity(0.7))
            Text(message)
                .font(SlabFont.sans(size: 12))
                .foregroundStyle(AppColor.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    private func loadHistory() async {
        if case .loaded = historyState { return }
        historyState = .loading
        do {
            let points = try await repository.priceHistory(
                productId: gain.productId,
                subType: gain.subTypeName,
                days: 90
            )
            historyState = .loaded(points)
        } catch {
            historyState = .error(String(describing: error))
        }
    }

    // MARK: - Helpers

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private func accessibilitySummary(points: [PriceHistoryDTO]) -> String {
        guard let first = points.first, let last = points.last else { return "" }
        let firstStr = MoversFormat.price(first.marketPrice)
        let lastStr  = MoversFormat.price(last.marketPrice)
        return "\(points.count) points from \(firstStr) on \(Self.day.string(from: first.capturedAt)) to \(lastStr) on \(Self.day.string(from: last.capturedAt))."
    }
}
