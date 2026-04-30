import Charts
import SwiftUI

/// Card-detail screen reached by tapping a row in the Movers tab.
/// Shows the static metadata that arrived with the mover row (image,
/// name, set, sub-type, current/previous price, abs/pct change) plus
/// a Swift Charts line chart of the last 90 days of market prices.
struct MoverDetailView: View {
    @State private var viewModel: MoverDetailViewModel

    init(mover: MoverDTO) {
        _viewModel = State(initialValue: MoverDetailViewModel(mover: mover))
    }

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    hero
                    statsCard
                    historyCard
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxxl)
            }
            .refreshable { await viewModel.refresh() }
        }
        .navigationTitle(viewModel.mover.productName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            heroImage
            VStack(alignment: .leading, spacing: Spacing.xs) {
                KickerLabel(viewModel.mover.subTypeName)
                Text(viewModel.mover.productName).slabTitle()
                if let set = viewModel.mover.groupName, !set.isEmpty {
                    Text(set)
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.muted)
                }
            }
        }
    }

    @ViewBuilder
    private var heroImage: some View {
        if let urlString = viewModel.mover.imageUrl, let url = URL(string: urlString) {
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
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(AppColor.dim)
            )
            .frame(height: 240)
    }

    // MARK: - Stats card

    private var statsCard: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        KickerLabel("Now")
                        Text(MoversFormat.price(viewModel.mover.currentPrice))
                            .slabMetric()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.xxs) {
                        KickerLabel("90d ago")
                        Text(MoversFormat.price(viewModel.mover.previousPrice))
                            .font(SlabFont.mono(size: 14))
                            .foregroundStyle(AppColor.muted)
                    }
                }

                Divider().background(AppColor.hairline)

                HStack(spacing: Spacing.l) {
                    statColumn(
                        label: "Change",
                        value: signedDollar(viewModel.mover.absChange),
                        tint: changeTint
                    )
                    statColumn(
                        label: "Move",
                        value: MoversFormat.percent(viewModel.mover.pctChange),
                        tint: changeTint
                    )
                    statColumn(
                        label: "Captured",
                        value: Self.day.string(from: viewModel.mover.capturedAt),
                        tint: AppColor.text
                    )
                }
            }
            .padding(Spacing.l)
        }
    }

    private func statColumn(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            KickerLabel(label)
            Text(value)
                .font(SlabFont.mono(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var changeTint: Color {
        viewModel.mover.pctChange >= 0 ? AppColor.positive : AppColor.negative
    }

    private func signedDollar(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "−"
        return "\(sign)\(MoversFormat.price(abs(value)))"
    }

    // MARK: - History chart

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                KickerLabel("90-day market price")
                Spacer()
                if case let .loaded(points) = viewModel.state, points.count >= 2 {
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
        switch viewModel.state {
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
        .accessibilityLabel("Price history")
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
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(isError ? AppColor.negative : AppColor.gold.opacity(0.7))
            Text(message)
                .font(SlabFont.sans(size: 12))
                .foregroundStyle(AppColor.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
