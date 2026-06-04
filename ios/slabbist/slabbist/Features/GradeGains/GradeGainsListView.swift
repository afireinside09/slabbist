import SwiftUI
import SwiftData

/// Grade Gains screen. A single ranked list of raw → PSA 10 upside
/// opportunities for one set + price tier, filtered server-side to
/// positive-after-fee profit. Mirrors `MoversListView`'s visual shell —
/// dark ink root, kicker + serif title, set search + chip rails,
/// `SlabCard` row groups — minus the gainers/losers split. Adds a
/// header grading-fee stepper that recomputes profit live.
struct GradeGainsListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = GradeGainViewModel()
    @State private var selectedGain: GradeGainDTO?
    @State private var setSearchQuery: String = ""
    @FocusState private var setSearchFocused: Bool
    /// Signal from the search-suggestion tap to the horizontal chip
    /// rail. The rail owns its own `ScrollViewReader`; writing this
    /// state requests a scroll, the rail's `.onChange` performs it and
    /// clears the signal. Mirrors `MoversListView`.
    @State private var scrollToSetId: Int?

    var body: some View {
        NavigationStack {
            SlabbedRoot {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xxl) {
                        header

                        feeControl

                        priceTierRail

                        setSearchField

                        setRail

                        if viewModel.isStale {
                            staleBanner
                        }

                        listBody

                        Spacer(minLength: Spacing.xxxl)
                    }
                    .padding(.top, Spacing.l)
                    .padding(.bottom, Spacing.xxxl)
                }
            }
            .overlay(alignment: .topTrailing) {
                SettingsGearButton()
                    .padding(.top, Spacing.l)
                    .padding(.trailing, Spacing.l)
            }
            .toolbar(.hidden, for: .navigationBar)
            // Keying on set + tier means any picker change kicks off
            // exactly one reload. The view-model dedupes inflight fetches.
            .task(id: "\(viewModel.selectedSet ?? -1)|\(viewModel.priceTier.rawValue)") {
                viewModel.attach(modelContext)
                await viewModel.load()
            }
            .navigationDestination(item: $selectedGain) { gain in
                GradeGainDetailView(gain: gain, feeCents: viewModel.feeCents)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Market")
            Text("Grade Gains").slabTitle()
            Text("Raw → PSA 10 upside")
                .font(SlabFont.mono(size: 13))
                .foregroundStyle(AppColor.muted)
        }
        .padding(.horizontal, Spacing.xxl)
    }

    /// Shown when the live fetch failed and the screen is displaying the
    /// persisted last-known-good rows, so the operator knows the data is
    /// stale (and from which filter) rather than mistaking it for fresh.
    private var staleBanner: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "wifi.slash")
                .font(SlabFont.sans(size: 13, weight: .regular))
            VStack(alignment: .leading, spacing: 2) {
                Text("Offline — showing last saved data")
                    .font(SlabFont.sans(size: 13, weight: .semibold))
                if let stamp = viewModel.staleFetchedAt {
                    Text("\(viewModel.staleContextLabel ?? "") · as of \(stamp.formatted(date: .abbreviated, time: .shortened))")
                        .font(SlabFont.mono(size: 11))
                        .foregroundStyle(AppColor.dim)
                }
            }
            Spacer()
        }
        .foregroundStyle(AppColor.muted)
        .padding(Spacing.m)
        .background(AppColor.elev, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .stroke(AppColor.hairline, lineWidth: 1)
        )
        .padding(.horizontal, Spacing.xxl)
    }

    // MARK: - Fee control
    //
    // A stepper that nudges the grading fee in $5 increments. Profit is
    // `spread − fee`, so raising the fee both shrinks each row's profit
    // and (via `visibleRows`) drops rows that fall to break-even or below.

    private var feeControl: some View {
        SlabCard {
            Stepper(value: $viewModel.feeCents, in: 0...100_000, step: 500) {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "scissors")
                        .font(SlabFont.sans(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.gold)
                    Text("Grading fee: \(feeDisplay)")
                        .font(SlabFont.sans(size: 14, weight: .medium))
                        .foregroundStyle(AppColor.text)
                }
            }
            .tint(AppColor.gold)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.md)
        }
        .padding(.horizontal, Spacing.xxl)
        .accessibilityLabel("Grading fee")
        .accessibilityValue(feeDisplay)
    }

    private var feeDisplay: String {
        (Double(viewModel.feeCents) / 100)
            .formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    // MARK: - Price tier rail

    private var priceTierRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Spacing.s) {
                ForEach(MoversPriceTier.pickerOptions) { tier in
                    GradeGainChip(
                        label: tier.displayName,
                        isSelected: viewModel.priceTier == tier
                    ) {
                        guard viewModel.priceTier != tier else { return }
                        viewModel.select(tier: tier)
                    }
                }
            }
            .padding(.horizontal, Spacing.xxl)
        }
        .accessibilityLabel("Price tier")
    }

    // MARK: - Set search

    @ViewBuilder
    private var setSearchField: some View {
        if !viewModel.sets.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SlabCard {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppColor.dim)
                            .frame(width: 18)
                        TextField(
                            "",
                            text: $setSearchQuery,
                            prompt: Text("Jump to a set").foregroundStyle(AppColor.dim)
                        )
                        .focused($setSearchFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.go)
                        .onSubmit {
                            if let first = filteredSets.first {
                                selectSet(first)
                            }
                        }
                        .foregroundStyle(AppColor.text)
                        .tint(AppColor.gold)
                        if !setSearchQuery.isEmpty {
                            Button {
                                setSearchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppColor.dim)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.md)
                }
                if !setSearchQuery.isEmpty {
                    suggestionsList
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Set search")
        }
    }

    @ViewBuilder
    private var suggestionsList: some View {
        let matches = filteredSets
        SlabCard {
            if matches.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColor.dim)
                    Text("No sets match \"\(setSearchQuery)\"")
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.muted)
                    Spacer()
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.md)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.groupId) { index, set in
                        if index > 0 { SlabCardDivider() }
                        Button {
                            selectSet(set)
                        } label: {
                            HStack(spacing: Spacing.s) {
                                Text(set.groupName)
                                    .font(SlabFont.sans(size: 14))
                                    .foregroundStyle(AppColor.text)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                Text("\(set.gainsCount)")
                                    .font(SlabFont.mono(size: 11))
                                    .foregroundStyle(AppColor.dim)
                                Image(systemName: "arrow.up.right")
                                    .font(SlabFont.sans(size: 11, weight: .semibold))
                                    .foregroundStyle(AppColor.dim)
                            }
                            .padding(.horizontal, Spacing.l)
                            .padding(.vertical, Spacing.md)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Picks this set and scrolls the rail")
                    }
                }
            }
        }
    }

    /// Up to 10 case-insensitive substring matches on `groupName`.
    private var filteredSets: [GradeGainSetDTO] {
        let query = setSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return viewModel.sets
            .filter { $0.groupName.lowercased().contains(query) }
            .prefix(10)
            .map { $0 }
    }

    private func selectSet(_ set: GradeGainSetDTO) {
        viewModel.select(set: set.groupId)
        setSearchQuery = ""
        setSearchFocused = false
        scrollToSetId = set.groupId
    }

    // MARK: - Set rail

    @ViewBuilder
    private var setRail: some View {
        if viewModel.sets.isEmpty {
            EmptyView()
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.s) {
                        ForEach(viewModel.sets) { set in
                            GradeGainChip(
                                label: set.groupName,
                                isSelected: viewModel.selectedSet == set.groupId
                            ) {
                                viewModel.select(set: set.groupId)
                            }
                            .id(set.groupId)
                        }
                    }
                    .padding(.horizontal, Spacing.xxl)
                }
                .accessibilityLabel("Set filter")
                .onChange(of: scrollToSetId) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    Task { @MainActor in
                        scrollToSetId = nil
                    }
                }
            }
        }
    }

    // MARK: - List body

    private var listBody: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "arrow.up.forward.square")
                    .font(SlabFont.sans(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.gold)
                KickerLabel("Profitable after fee")
                Spacer()
                countBadge
            }
            SlabCard {
                GradeGainsSectionBody(
                    section: viewModel.section,
                    rows: viewModel.visibleRows,
                    feeCents: viewModel.feeCents
                ) { gain in
                    selectedGain = gain
                }
            }
        }
        .padding(.horizontal, Spacing.xxl)
    }

    @ViewBuilder
    private var countBadge: some View {
        let rows = viewModel.visibleRows
        if case .loaded = viewModel.section, !rows.isEmpty {
            Text("\(rows.count)")
                .font(SlabFont.mono(size: 11, weight: .semibold))
                .foregroundStyle(AppColor.gold)
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(AppColor.gold.opacity(0.12))
                )
        }
    }
}

// MARK: - Chip
//
// Same compact pill used in `MoversListView`'s rails. Re-declared here
// (the Movers version is `private`) so this screen stays self-contained.

private struct GradeGainChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(SlabFont.sans(size: 12, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(isSelected ? AppColor.ink : AppColor.text)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.s)
                .background(
                    RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                        .fill(isSelected ? AppColor.gold : AppColor.elev)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                        .stroke(isSelected ? Color.clear : AppColor.hairline, lineWidth: 1)
                )
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Section body

/// State-machine wrapper for the single ranked list. Idle/loading show
/// skeleton rows; loaded shows the `visibleRows` (already filtered to
/// positive-after-fee profit by the view-model) or an empty state;
/// error shows the failure copy.
private struct GradeGainsSectionBody: View {
    let section: GradeGainSection
    let rows: [GradeGainDTO]
    let feeCents: Int
    let onSelect: (GradeGainDTO) -> Void

    var body: some View {
        switch section {
        case .idle, .loading:
            GradeGainSkeletonRows(count: 6)
        case .loaded:
            if rows.isEmpty {
                EmptyGradeGainsRow()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, gain in
                        if index > 0 { SlabCardDivider() }
                        GradeGainRow(rank: index + 1, gain: gain, feeCents: feeCents) {
                            onSelect(gain)
                        }
                    }
                }
            }
        case let .error(message):
            ErrorGradeGainsRow(message: message)
        }
    }
}

// MARK: - Row

private struct GradeGainRow: View {
    let rank: Int
    let gain: GradeGainDTO
    let feeCents: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: Spacing.m) {
                Text(String(format: "%02d", rank))
                    .font(SlabFont.mono(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.dim)
                    .frame(width: 22, alignment: .leading)

                thumbnail

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(gain.productName)
                            .slabRowTitle()
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let badge = MoversFormat.variantBadge(gain.subTypeName) {
                            Text(badge)
                                .font(SlabFont.mono(size: 10, weight: .medium))
                                .foregroundStyle(AppColor.gold.opacity(0.85))
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                        .fill(AppColor.gold.opacity(0.12))
                                )
                                .lineLimit(1)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityHidden(true)
                        }
                    }
                    if let set = gain.groupName, !set.isEmpty {
                        Text(set)
                            .font(SlabFont.sans(size: 11))
                            .foregroundStyle(AppColor.dim)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: Spacing.s)

                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    Text(GradeGainFormat.money(gain.profitCents(feeCents: feeCents)))
                        .font(SlabFont.mono(size: 16, weight: .semibold))
                        .foregroundStyle(AppColor.gold)
                    Text(spreadLabel)
                        .font(SlabFont.mono(size: 11))
                        .foregroundStyle(AppColor.dim)
                }

                Image(systemName: "chevron.right")
                    .font(SlabFont.sans(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.dim)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint("Opens grade-gain detail")
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(AppColor.elev2)
            if let urlString = gain.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .empty, .failure:
                        Image(systemName: "photo")
                            .font(SlabFont.sans(size: 14))
                            .foregroundStyle(AppColor.dim)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "photo")
                    .font(SlabFont.sans(size: 14))
                    .foregroundStyle(AppColor.dim)
            }
        }
        .frame(width: 40, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        .accessibilityHidden(true)
    }

    private var spreadLabel: String {
        "\(GradeGainFormat.money(gain.rawPriceCents)) → \(GradeGainFormat.money(gain.psa10PriceCents))"
    }

    private var accessibilityLabel: String {
        let set = gain.groupName.map { ", \($0)" } ?? ""
        let variant = MoversFormat.variantBadge(gain.subTypeName).map { ", \($0)" } ?? ""
        let profit = GradeGainFormat.money(gain.profitCents(feeCents: feeCents))
        return "Rank \(rank). \(gain.productName)\(variant)\(set). Profit \(profit), \(spreadLabel)."
    }
}

// MARK: - Skeleton / empty / error

private struct GradeGainSkeletonRows: View {
    let count: Int
    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                if index > 0 { SlabCardDivider() }
                HStack(spacing: Spacing.m) {
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(AppColor.elev2)
                        .frame(width: 22, height: 10)

                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(AppColor.elev2)
                        .frame(width: 40, height: 56)

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
                            .frame(width: 80, height: 10)
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.md)
                .opacity(shimmer ? 0.55 : 1.0)
            }
        }
        .onAppear { shimmer = true }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
            value: shimmer
        )
    }
}

private struct EmptyGradeGainsRow: View {
    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "arrow.up.forward.square")
                .font(SlabFont.sans(size: 32, weight: .regular))
                .foregroundStyle(AppColor.gold.opacity(0.7))
                .padding(.top, Spacing.l)
            Text("No gains in this band")
                .font(SlabFont.serif(size: 22))
                .tracking(-0.5)
                .foregroundStyle(AppColor.text)
            Text("Nothing clears the grading fee for this set and price tier. Try a lower fee, a different tier, or another set.")
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

private struct ErrorGradeGainsRow: View {
    let message: String

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(SlabFont.sans(size: 24, weight: .regular))
                .foregroundStyle(AppColor.negative)
                .padding(.top, Spacing.l)
            Text("Couldn’t load grade gains")
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

/// Cent-based money formatter for grade-gain figures. Shared by the row
/// and detail view. Cents in, "$25" / "$3.50" out (0–2 fraction digits).
enum GradeGainFormat {
    static func money(_ cents: Int) -> String {
        (Double(cents) / 100)
            .formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }
}
