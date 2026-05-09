import SwiftUI

/// Top movers screen. Shows the 10 biggest gainers and 10 biggest
/// losers for either Pokémon English or Pokémon Japanese, side by
/// side in stacked cards. Mirrors the `LotsListView` shell — dark ink
/// root, kicker + serif title, `SlabCard` row groups — so the tab
/// feels like part of the same app.
struct MoversListView: View {
    @State private var viewModel = MoversViewModel()
    @State private var selectedMover: MoverDTO?
    @State private var selectedEbayProduct: EbayProductGroup?
    @State private var setSearchQuery: String = ""
    @FocusState private var setSearchFocused: Bool
    /// Signal from the search-suggestion tap to the horizontal chip
    /// rail. The rail owns its own `ScrollViewReader` so the proxy
    /// scrolls the rail (not the outer vertical page); writing this
    /// state from the search field requests a scroll, the rail's
    /// `.onChange` handler performs it and clears the signal.
    @State private var scrollToSetId: Int?

    var body: some View {
        NavigationStack {
            SlabbedRoot {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xxl) {
                        header

                        tabPicker

                        priceTierRail

                        setSearchField

                        setRail

                        tabBody

                        Spacer(minLength: Spacing.xxxl)
                    }
                    .padding(.top, Spacing.l)
                    .padding(.bottom, Spacing.xxxl)
                }
                .refreshable { await viewModel.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
            // Keying on tab + set + tier means any picker change kicks
            // off exactly one reload. Caches in the view-model make
            // repeat visits to the same combo a synchronous no-op.
            .task(id: filterFingerprint) {
                await viewModel.loadIfNeeded()
            }
            .navigationDestination(item: $selectedMover) { mover in
                MoverDetailView(mover: mover)
            }
            .navigationDestination(item: $selectedEbayProduct) { group in
                EbayProductListingsView(group: group)
            }
            // Tab/language change wipes the search context — the
            // cached suggestion list is the *previous* tab's set list.
            .onChange(of: viewModel.tab) { _, _ in
                setSearchQuery = ""
                setSearchFocused = false
            }
        }
    }

    /// Stable hashable for `.task(id:)`. A struct keeps the comparison
    /// explicit and avoids a tuple-of-Hashable runtime cost.
    private var filterFingerprint: FilterKey {
        FilterKey(
            tab: viewModel.tab,
            filter: viewModel.setFilter,
            priceTier: viewModel.priceTier
        )
    }
    private struct FilterKey: Hashable {
        let tab: MoversTab
        let filter: Int?
        let priceTier: MoversPriceTier
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
        .padding(.horizontal, Spacing.xxl)
    }

    private var subtitle: String {
        let scope = scopeLabel
        if let stamp = viewModel.lastUpdatedAt {
            let rel = Self.relative.localizedString(for: stamp, relativeTo: Date())
            return "\(scope) · updated \(rel)"
        }
        return scope
    }

    private var scopeLabel: String {
        let setPart: String
        if let id = viewModel.setFilter,
           let name = viewModel.currentSets.first(where: { $0.groupId == id })?.groupName {
            setPart = name
        } else if viewModel.tab == .ebayListings {
            setPart = "eBay listings"
        } else {
            setPart = "\(viewModel.language.displayName) sets"
        }
        return "\(setPart) · \(viewModel.priceTier.displayName)"
    }

    // MARK: - Tab picker
    //
    // Three-option segmented control. English / Japanese drive the
    // movers slates; eBay Listings switches the screen into a flat
    // browse over `mover_ebay_listings`. Each tab keeps its own
    // (setFilter, priceTier) so flipping doesn't lose the user's
    // place — the view-model handles the snapshot/restore.

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(MoversTab.allCases) { tab in
                    SetChip(
                        label: tab.displayName,
                        isSelected: viewModel.tab == tab
                    ) {
                        viewModel.switchTab(to: tab)
                    }
                }
            }
            .padding(.horizontal, Spacing.xxl)
        }
        .accessibilityLabel("Movers tab")
    }

    // MARK: - Price tier rail
    //
    // Sits between the language picker and the set rail. The set
    // filter is intentionally NOT touched when the tier changes —
    // users want to compare tiers within the same set, and the rail
    // shows every set with any mover so the selection stays visible
    // even when the new tier is sparse for that set.

    private var priceTierRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Spacing.s) {
                ForEach(visibleTiers) { tier in
                    SetChip(
                        label: tier.displayName,
                        isSelected: viewModel.priceTier == tier
                    ) {
                        guard viewModel.priceTier != tier else { return }
                        viewModel.priceTier = tier
                    }
                }
            }
            .padding(.horizontal, Spacing.xxl)
        }
        .accessibilityLabel("Price tier")
    }

    /// Tier rail source. Movers mode shows every tier (the user can
    /// always pick one and we'll show "no movers in this band" if
    /// it's empty). eBay mode hides tiers with zero listings for
    /// the currently-selected set so the user can't tap into a band
    /// with nothing in it.
    private var visibleTiers: [MoversPriceTier] {
        switch viewModel.tab {
        case .english, .japanese: return MoversPriceTier.pickerOptions
        case .ebayListings:       return viewModel.availableEbayTiers
        }
    }

    // MARK: - Set search
    //
    // Compact text field above the horizontal rail. Substring filter
    // on `groupName`, capped at 10 hits to keep the dropdown bounded.
    // Tapping a suggestion sets the filter, clears the query, defocus-
    // es the keyboard, and scrolls the rail so the picked chip lands
    // in the middle — gives the user visible confirmation that the
    // selection landed on the rail they were already familiar with.

    @ViewBuilder
    private var setSearchField: some View {
        if !viewModel.currentSets.isEmpty {
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
                            // Pressing return picks the first match
                            // — common pattern for search inputs.
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
                                Text("\(set.moversCount)")
                                    .font(SlabFont.mono(size: 11))
                                    .foregroundStyle(AppColor.dim)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .semibold))
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
    /// 10 is enough to comfortably scroll a dropdown without making
    /// it the dominant element on the screen.
    private var filteredSets: [MoversSetDTO] {
        let query = setSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return viewModel.currentSets
            .filter { $0.groupName.lowercased().contains(query) }
            .prefix(10)
            .map { $0 }
    }

    private func selectSet(_ set: MoversSetDTO) {
        viewModel.setFilter = set.groupId
        setSearchQuery = ""
        setSearchFocused = false
        // The rail observes this via .onChange and performs the
        // scroll inside its own ScrollViewReader scope.
        scrollToSetId = set.groupId
    }

    // MARK: - Set rail
    //
    // Horizontal scroll of chips, one per set with at least one mover
    // somewhere in any tier. ~200 sets per language can show up here,
    // so the chips are width-hugging and the scroll view is the only
    // viable layout. `LazyHStack` defers off-screen chips. Each chip
    // carries `.id(groupId)` so the search field can scroll the rail
    // to reveal a picked set.

    @ViewBuilder
    private var setRail: some View {
        if viewModel.currentSets.isEmpty && viewModel.setsLoadError == nil {
            // Either still loading or no sets-with-movers exist yet.
            EmptyView()
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.s) {
                        // Both modes auto-bootstrap to a specific
                        // set (movers: newest set with movers; eBay:
                        // newest set with listings) — no "all sets"
                        // affordance, the user always lands on real
                        // data.
                        ForEach(viewModel.currentSets) { set in
                            SetChip(
                                label: set.groupName,
                                isSelected: viewModel.setFilter == set.groupId
                            ) {
                                viewModel.setFilter = set.groupId
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

    // MARK: - Body switch

    @ViewBuilder
    private var tabBody: some View {
        switch viewModel.tab {
        case .english, .japanese:
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                gainersSection
                losersSection
            }
        case .ebayListings:
            ebayListingsSection
        }
    }

    // MARK: - eBay listings section

    private var ebayListingsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "tag")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.gold)
                KickerLabel("Pokémon products with listings")
                Spacer()
                if case let .loaded(rows) = viewModel.ebayListingsState, !rows.isEmpty {
                    Text("\(rows.groupedByProduct().count)")
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
            Text("Affiliate links — Slabbist may earn a commission.")
                .font(SlabFont.sans(size: 11))
                .foregroundStyle(AppColor.dim)
            SlabCard {
                MoversEbayProductsBody(
                    state: viewModel.ebayListingsState,
                    onSelect: { group in selectedEbayProduct = group }
                )
            }
        }
        .padding(.horizontal, Spacing.xxl)
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
                MoversSectionBody(state: state, direction: direction) { mover in
                    selectedMover = mover
                }
            }
        }
        .padding(.horizontal, Spacing.xxl)
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

// MARK: - Set chip
//
// Compact pill used in the horizontal set rail. Visually mirrors the
// .neutral PillToggle style (ink elev backdrop, gold-on-selection)
// without the full segmented-control affordance — chips here are
// independent buttons, not a single selection control.

private struct SetChip: View {
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
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Section body

/// Extracted subview so SwiftUI can diff the section independently —
/// a re-fetch of gainers doesn't force losers to re-render. The
/// `onSelect` closure receives a tapped row's `MoverDTO`; the parent
/// view assigns it to `selectedMover` to push the detail screen.
private struct MoversSectionBody: View {
    let state: MoversViewModel.SectionState
    let direction: MoversDirection
    let onSelect: (MoverDTO) -> Void

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
                        MoverRow(rank: index + 1, mover: mover, direction: direction) {
                            onSelect(mover)
                        }
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
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: Spacing.m) {
                Text(String(format: "%02d", rank))
                    .font(SlabFont.mono(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.dim)
                    .frame(width: 22, alignment: .leading)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(mover.productName)
                            .slabRowTitle()
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let badge = MoversFormat.variantBadge(mover.subTypeName) {
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
                                .fixedSize()
                                .accessibilityHidden(true)
                        }
                    }
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

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.dim)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint("Opens price history")
    }

    private var accessibilityLabel: String {
        let pct = MoversFormat.percent(mover.pctChange)
        let set = mover.groupName.map { ", \($0)" } ?? ""
        let variant = MoversFormat.variantBadge(mover.subTypeName).map { ", \($0)" } ?? ""
        return "Rank \(rank). \(mover.productName)\(variant)\(set). \(MoversFormat.price(mover.currentPrice)). \(pct)."
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

// MARK: - eBay listings list (browse mode)

/// State-machine wrapper for the eBay-Listings tab body. Folds the
/// flat listings payload into product-level groups so the user sees
/// Pokémon products first; tapping a product drills into its
/// associated listings. This swap is purely a client-side
/// presentation change — the underlying RPC still returns flat rows.
private struct MoversEbayProductsBody: View {
    let state: MoversViewModel.EbayBrowseState
    let onSelect: (EbayProductGroup) -> Void

    var body: some View {
        switch state {
        case .idle, .loading:
            SkeletonRows(count: 6)
        case let .loaded(rows):
            let groups = rows.groupedByProduct()
            if groups.isEmpty {
                EbayEmptyRow()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { SlabCardDivider() }
                        EbayProductRow(group: group, onTap: { onSelect(group) })
                    }
                }
            }
        case let .error(message):
            ErrorMoversRow(message: message)
        }
    }
}

private struct EbayProductRow: View {
    let group: EbayProductGroup
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: Spacing.m) {
                thumbnail
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(group.productName)
                            .slabRowTitle()
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let badge = MoversFormat.variantBadge(group.subTypeName) {
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
                                .fixedSize()
                        }
                    }
                    if let set = group.groupName, !set.isEmpty {
                        Text(set)
                            .font(SlabFont.sans(size: 11))
                            .foregroundStyle(AppColor.dim)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(listingsLabel)
                        .font(SlabFont.mono(size: 11))
                        .foregroundStyle(AppColor.gold)
                }
                Spacer(minLength: Spacing.s)
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    if let minPrice = group.minPrice {
                        Text(MoversFormat.price(minPrice))
                            .slabMetric()
                        if let maxPrice = group.maxPrice, maxPrice > minPrice {
                            Text("up to \(MoversFormat.price(maxPrice))")
                                .font(SlabFont.mono(size: 10))
                                .foregroundStyle(AppColor.dim)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.dim)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens this product's eBay listings")
    }

    private var listingsLabel: String {
        let n = group.listingCount
        return "\(n) live \(n == 1 ? "listing" : "listings")"
    }

    private var accessibilityLabel: String {
        let variant = MoversFormat.variantBadge(group.subTypeName).map { ", \($0)" } ?? ""
        let set = group.groupName.map { ", \($0)" } ?? ""
        let priceFrom = group.minPrice.map { ", from \(MoversFormat.price($0))" } ?? ""
        return "\(group.productName)\(variant)\(set), \(group.listingCount) listings\(priceFrom)"
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(AppColor.elev2)
            if let urlString = group.displayImageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .empty, .failure:
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(AppColor.dim)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
    }
}

private struct EbayEmptyRow: View {
    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "tag")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(AppColor.gold.opacity(0.7))
                .padding(.top, Spacing.l)
            Text("No listings yet")
                .font(SlabFont.serif(size: 22))
                .tracking(-0.5)
                .foregroundStyle(AppColor.text)
            Text("Run the scraper to populate eBay listings, or pick a different price tier or set.")
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

    /// Short label for a card variant, returned as a row badge next
    /// to the product name. Returns `nil` for `Normal` (the implied
    /// default — no badge) so the common case stays uncluttered.
    static func variantBadge(_ subTypeName: String) -> String? {
        switch subTypeName {
        case "Normal":
            return nil
        case "Holofoil":
            return "Holo"
        case "Reverse Holofoil":
            return "Reverse Holo"
        case "1st Edition":
            return "1st Ed"
        case "1st Edition Holofoil":
            return "1st Ed Holo"
        case "Unlimited":
            return "Unlimited"
        case "Unlimited Holofoil":
            return "Unlimited Holo"
        default:
            return subTypeName
        }
    }
}
