import SwiftUI
import SwiftData

/// Combined sheet for adjusting a lot's margin override and editing the
/// store-wide margin ladder. Replaces `MarginPickerSheet` as the target
/// of the "Adjust" button in `LotDetailView`.
///
/// The lot override and the store ladder save independently — lot override
/// dismisses the sheet; ladder save stays open for further edits.
struct LotMarginSheet: View {
    let currentPct: Double
    let storeId: UUID
    let onSelectLotMargin: (Double) -> Void

    @Environment(\.modelContext) private var context
    @Environment(OutboxKicker.self) private var kicker
    @Environment(\.dismiss) private var dismiss

    @State private var pct: Double
    @State private var tiers: [Row] = []
    @State private var initialTiers: [MarginTier] = []
    @State private var ladderError: String?

    private static let snaps: [Double] = [0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00]

    init(currentPct: Double, storeId: UUID, onSelectLotMargin: @escaping (Double) -> Void) {
        self.currentPct = currentPct
        self.storeId = storeId
        self.onSelectLotMargin = onSelectLotMargin
        _pct = State(initialValue: currentPct)
    }

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    lotSection
                    ladderSection
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.vertical, Spacing.l)
            }
        }
        .task { loadLadder() }
    }

    // MARK: - Lot override section

    private var lotSection: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            KickerLabel("Lot margin override")
            Text("\(Int((pct * 100).rounded()))% of comp").slabTitle()
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 56), spacing: Spacing.s)],
                alignment: .leading,
                spacing: Spacing.s
            ) {
                ForEach(Self.snaps, id: \.self) { snap in
                    Button("\(Int(snap * 100))%") { pct = snap }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.s)
                        .background(snap == pct ? AppColor.gold.opacity(0.2) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColor.gold, lineWidth: snap == pct ? 1.5 : 0.5)
                        )
                        .accessibilityIdentifier("margin-snap-\(Int(snap * 100))")
                }
            }
            Slider(value: $pct, in: 0.70...1.00, step: 0.01)
                .accessibilityIdentifier("margin-slider")
            PrimaryGoldButton(title: "Save lot margin") {
                onSelectLotMargin(pct)
                dismiss()
            }
            .accessibilityIdentifier("margin-save")
        }
    }

    // MARK: - Store ladder section

    private var ladderSection: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            KickerLabel("Margin ladder")
            Text("Changes apply to all future auto-priced lots.")
                .font(SlabFont.sans(size: 13))
                .foregroundStyle(AppColor.muted)
            SlabCard {
                VStack(spacing: 0) {
                    ForEach(tiers) { row in
                        if row.id != tiers.first?.id { SlabCardDivider() }
                        tierRow(row)
                    }
                    SlabCardDivider()
                    Button {
                        let nextCents: Int64 = (tiers.map(\.cents).max() ?? 0) + 50_000
                        tiers.insert(Row(id: UUID(), cents: nextCents, pct: 0.80), at: 0)
                        ladderError = nil
                    } label: {
                        HStack(spacing: Spacing.s) {
                            Image(systemName: "plus")
                                .font(SlabFont.sans(size: 13, weight: .semibold))
                            Text("Add tier")
                                .font(SlabFont.sans(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(AppColor.gold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("margin-ladder-add")
                }
            }
            if let ladderError {
                Text(ladderError)
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.negative)
                    .accessibilityIdentifier("margin-ladder-error")
            }
            PrimaryGoldButton(title: "Save ladder", isEnabled: hasLadderChanges) {
                saveLadder()
            }
            .accessibilityIdentifier("margin-ladder-save")
            Button("Reset to defaults") {
                tiers = Self.makeRows(from: .defaultMarginLadder)
                ladderError = nil
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.muted)
            .accessibilityIdentifier("margin-ladder-reset")
        }
    }

    @ViewBuilder
    private func tierRow(_ row: Row) -> some View {
        let binding = Binding<Row>(
            get: { tiers.first(where: { $0.id == row.id }) ?? row },
            set: { new in
                if let idx = tiers.firstIndex(where: { $0.id == new.id }) {
                    tiers[idx] = new
                }
            }
        )
        HStack(alignment: .center, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                KickerLabel("If comp ≥")
                HStack(spacing: Spacing.xs) {
                    Text("$")
                        .font(SlabFont.mono(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.dim)
                    TextField("0", text: binding.dollarsText)
                        .keyboardType(.numberPad)
                        .font(SlabFont.mono(size: 14, weight: .semibold))
                        .frame(minWidth: 60)
                        .accessibilityIdentifier("margin-ladder-cents-\(row.id)")
                }
            }
            Spacer(minLength: Spacing.m)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                KickerLabel("Pay")
                HStack(spacing: Spacing.xs) {
                    TextField("70", text: binding.percentText)
                        .keyboardType(.numberPad)
                        .font(SlabFont.mono(size: 14, weight: .semibold))
                        .frame(minWidth: 44)
                        .accessibilityIdentifier("margin-ladder-pct-\(row.id)")
                    Text("%")
                        .font(SlabFont.mono(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.dim)
                }
            }
            Button {
                tiers.removeAll { $0.id == row.id }
                ladderError = nil
            } label: {
                Image(systemName: "minus.circle")
                    .font(SlabFont.sans(size: 16, weight: .regular))
                    .foregroundStyle(AppColor.dim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tier")
            .accessibilityIdentifier("margin-ladder-remove-\(row.id)")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Ladder data

    private var hasLadderChanges: Bool {
        tiers.compactMap(\.materialized).canonicalized() != initialTiers
    }

    private func loadLadder() {
        var descriptor = FetchDescriptor<Store>(predicate: #Predicate { $0.id == storeId })
        descriptor.fetchLimit = 1
        guard let store = try? context.fetch(descriptor).first else { return }
        let canonical = store.marginLadder.canonicalized()
        initialTiers = canonical
        tiers = Self.makeRows(from: canonical)
    }

    private func saveLadder() {
        let materialized = tiers.compactMap(\.materialized)
        guard materialized.count == tiers.count else {
            ladderError = "Each tier needs a comp threshold and a margin between 1–100%."
            return
        }
        guard !materialized.isEmpty else {
            ladderError = "Add at least one tier."
            return
        }
        let repo = StoreSettingsRepository(context: context, kicker: kicker, currentStoreId: storeId)
        do {
            try repo.updateMarginLadder(materialized)
            initialTiers = materialized.canonicalized()
            ladderError = nil
        } catch {
            ladderError = error.localizedDescription
        }
    }

    private static func makeRows(from tiers: [MarginTier]) -> [Row] {
        tiers.canonicalized().map { Row(id: UUID(), cents: $0.minCompCents, pct: $0.marginPct) }
    }

    // MARK: - Row model (mirrors MarginLadderView.Row, kept private to this file)

    fileprivate struct Row: Identifiable, Equatable {
        let id: UUID
        var cents: Int64
        var pct: Double

        var materialized: MarginTier? {
            guard cents >= 0, pct > 0, pct <= 1 else { return nil }
            return MarginTier(minCompCents: cents, marginPct: pct)
        }
    }
}

// MARK: - Bindings (mirrors MarginLadderView binding extensions)

private extension Binding where Value == LotMarginSheet.Row {
    var dollarsText: Binding<String> {
        Binding<String>(
            get: { String(wrappedValue.cents / 100) },
            set: { new in
                let digits = new.filter(\.isNumber)
                wrappedValue.cents = (Int64(digits) ?? 0) * 100
            }
        )
    }

    var percentText: Binding<String> {
        Binding<String>(
            get: { String(Int((wrappedValue.pct * 100).rounded())) },
            set: { new in
                let digits = new.filter(\.isNumber)
                guard let pct = Int(digits) else { wrappedValue.pct = 0; return }
                let clamped = Swift.min(Swift.max(pct, 0), 100)
                wrappedValue.pct = Double(clamped) / 100.0
            }
        )
    }
}
