import SwiftUI

/// Top movers screen. Shows the 10 biggest gainers and 10 biggest
/// losers for either Pokémon English or Pokémon Japanese, side by
/// side in stacked cards. Mirrors the `LotsListView` shell — dark ink
/// root, kicker + serif title, `SlabCard` row groups — so the tab
/// feels like part of the same app.
struct MoversListView: View {
    @State private var viewModel = MoversViewModel()

    var body: some View {
        NavigationStack {
            SlabbedRoot {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xxl) {
                        header

                        languagePicker

                        gainersSection
                        losersSection

                        Spacer(minLength: Spacing.xxxl)
                    }
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.top, Spacing.l)
                    .padding(.bottom, Spacing.xxxl)
                }
                .refreshable { await viewModel.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: viewModel.language) {
                await viewModel.loadIfNeeded()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Market")
            Text("Top movers").slabTitle()
            Text(subtitle)
                .font(SlabFont.mono(size: 13))
                .foregroundStyle(AppColor.muted)
        }
    }

    private var subtitle: String {
        if let stamp = viewModel.lastUpdatedAt {
            let rel = Self.relative.localizedString(for: stamp, relativeTo: Date())
            return "Tracking 24h moves · updated \(rel)"
        }
        return "Tracking 24h moves in Pokémon TCG"
    }

    // MARK: - Language picker

    private var languagePicker: some View {
        PillToggle(
            selection: Binding(
                get: { viewModel.language },
                set: { viewModel.language = $0 }
            ),
            options: MoversLanguage.allCases.map { ($0, $0.displayName) },
            style: .accent
        )
        .accessibilityLabel("Language")
    }

    // MARK: - Sections

    private var gainersSection: some View {
        moversSection(
            title: "Top gainers",
            systemImage: "arrow.up.right",
            tint: AppColor.positive,
            direction: .gainers,
            state: viewModel.gainers
        )
    }

    private var losersSection: some View {
        moversSection(
            title: "Top losers",
            systemImage: "arrow.down.right",
            tint: AppColor.negative,
            direction: .losers,
            state: viewModel.losers
        )
    }

    @ViewBuilder
    private func moversSection(
        title: String,
        systemImage: String,
        tint: Color,
        direction: MoversDirection,
        state: MoversViewModel.SectionState
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                KickerLabel(title)
                Spacer()
                leadBadge(for: state, direction: direction)
            }

            SlabCard {
                MoversSectionBody(state: state, direction: direction)
            }
        }
    }

    @ViewBuilder
    private func leadBadge(
        for state: MoversViewModel.SectionState,
        direction: MoversDirection
    ) -> some View {
        if case let .loaded(rows) = state, let lead = rows.first {
            Text(MoversFormat.percent(lead.pctChange))
                .font(SlabFont.mono(size: 11, weight: .semibold))
                .foregroundStyle(direction == .gainers ? AppColor.positive : AppColor.negative)
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill((direction == .gainers ? AppColor.positive : AppColor.negative).opacity(0.12))
                )
        }
    }

    // MARK: - Helpers

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}

// MARK: - Section body

/// Extracted subview so SwiftUI can diff the section independently —
/// a re-fetch of gainers doesn't force losers to re-render.
private struct MoversSectionBody: View {
    let state: MoversViewModel.SectionState
    let direction: MoversDirection

    var body: some View {
        switch state {
        case .idle, .loading:
            SkeletonRows(count: 6)
        case let .loaded(rows):
            if rows.isEmpty {
                EmptyMoversRow(direction: direction)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, mover in
                        if index > 0 {
                            SlabCardDivider()
                        }
                        MoverRow(rank: index + 1, mover: mover, direction: direction)
                    }
                }
            }
        case let .error(message):
            ErrorMoversRow(message: message)
        }
    }
}

// MARK: - Row

private struct MoverRow: View {
    let rank: Int
    let mover: MoverDTO
    let direction: MoversDirection

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Text(String(format: "%02d", rank))
                .font(SlabFont.mono(size: 12, weight: .medium))
                .foregroundStyle(AppColor.dim)
                .frame(width: 22, alignment: .leading)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(mover.productName)
                    .slabRowTitle()
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let set = mover.groupName, !set.isEmpty {
                    Text(set)
                        .font(SlabFont.sans(size: 11))
                        .foregroundStyle(AppColor.dim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: Spacing.s)

            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(MoversFormat.price(mover.currentPrice))
                    .slabMetric()
                PercentChip(value: mover.pctChange, direction: direction)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        let pct = MoversFormat.percent(mover.pctChange)
        let set = mover.groupName.map { ", \($0)" } ?? ""
        return "Rank \(rank). \(mover.productName)\(set). \(MoversFormat.price(mover.currentPrice)). \(pct)."
    }
}

// MARK: - % chip

private struct PercentChip: View {
    let value: Double
    let direction: MoversDirection

    var body: some View {
        let tint = direction == .gainers ? AppColor.positive : AppColor.negative
        Text(MoversFormat.percent(value))
            .font(SlabFont.mono(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

// MARK: - Skeleton / empty / error

private struct SkeletonRows: View {
    let count: Int
    @State private var shimmer = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                if index > 0 {
                    SlabCardDivider()
                }
                HStack(spacing: Spacing.m) {
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(AppColor.elev2)
                        .frame(width: 22, height: 10)

                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(AppColor.elev2)
                            .frame(height: 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(AppColor.elev2)
                            .frame(width: 96, height: 8)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(AppColor.elev2)
                            .frame(width: 56, height: 12)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(AppColor.elev2)
                            .frame(width: 40, height: 10)
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.md)
                .opacity(shimmer ? 0.55 : 1.0)
            }
        }
        .onAppear { shimmer = true }
        .animation(
            .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
            value: shimmer
        )
    }
}

private struct EmptyMoversRow: View {
    let direction: MoversDirection

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "chart.line.flattrend.xyaxis")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(AppColor.gold.opacity(0.7))
                .padding(.top, Spacing.l)
            Text("No \(direction.displayName.lowercased()) yet")
                .font(SlabFont.serif(size: 22))
                .tracking(-0.5)
                .foregroundStyle(AppColor.text)
            Text("Movers appear once a second price snapshot lands. Check back after the next sync.")
                .font(SlabFont.sans(size: 13))
                .foregroundStyle(AppColor.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.l)
            Spacer(minLength: Spacing.l)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Spacing.m)
    }
}

private struct ErrorMoversRow: View {
    let message: String

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(AppColor.negative)
                .padding(.top, Spacing.l)
            Text("Couldn’t load movers")
                .font(SlabFont.sans(size: 14, weight: .medium))
                .foregroundStyle(AppColor.text)
            Text(message)
                .font(SlabFont.sans(size: 12))
                .foregroundStyle(AppColor.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.l)
            Spacer(minLength: Spacing.m)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Spacing.m)
    }
}

// MARK: - Formatting

/// Small pure formatter used by the row, chip, and lead badge.
/// Extracted as an enum so tests (or future locales) can cover it
/// without spinning up SwiftUI.
enum MoversFormat {
    /// NumberFormatter with `.currency` style varies the spacing
    /// between symbol and digits across SDK versions. Keep the symbol
    /// under direct control and format only the digits.
    private static let digitGroupFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        // Default `.halfEven` rounds 12.345 down to 12.34 (banker's
        // rounding). For prices we want the commercial convention.
        f.roundingMode = .halfUp
        return f
    }()

    static func price(_ value: Double) -> String {
        let digits = digitGroupFormatter.string(from: NSNumber(value: value))
            ?? String(format: "%.2f", value)
        return "$" + digits
    }

    /// Formats like `+3.5%` / `-2.1%`. Caps absolute magnitude display
    /// at `99.9%` so a runaway value doesn't break row layout.
    static func percent(_ value: Double) -> String {
        let capped = max(-999.9, min(999.9, value))
        let sign = capped >= 0 ? "+" : ""
        return String(format: "\(sign)%.1f%%", capped)
    }
}
