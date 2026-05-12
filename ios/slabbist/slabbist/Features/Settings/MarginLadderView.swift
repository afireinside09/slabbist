import SwiftUI
import SwiftData

/// Per-store editor for the auto-pricing margin ladder. Each row maps a
/// reconciled-comp threshold (in cents, edited in dollars) to the offer
/// percentage applied to slabs at or above that threshold.
///
/// Persists via `StoreSettingsRepository.updateMarginLadder` — local
/// SwiftData write + outbox patch + drainer kick — so the new ladder is
/// visible to the next auto-derived buy price even before the network
/// round-trip completes. Reset reverts the working copy to the canonical
/// default ladder (does not write until the user taps Save).
struct MarginLadderView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(OutboxKicker.self) private var kicker
    @Environment(\.dismiss) private var dismiss

    @State private var tiers: [Row] = []
    @State private var storeId: UUID?
    @State private var error: String?
    @State private var initialTiers: [MarginTier] = []

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    intro
                    laddersSection
                    actionStack
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .navigationTitle("Margin ladder")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.userId) { loadFromStore() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Auto-pricing")
            Text("Margin ladder").slabTitle()
        }
    }

    private var intro: some View {
        Text("Set the offer percentage you'll pay based on a slab's comp value. The highest tier whose threshold a slab clears applies.")
            .font(SlabFont.sans(size: 13))
            .foregroundStyle(AppColor.muted)
    }

    private var laddersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Tiers")
            SlabCard {
                VStack(spacing: 0) {
                    ForEach(tiers) { row in
                        if row.id != tiers.first?.id { SlabCardDivider() }
                        tierRow(row)
                    }
                    SlabCardDivider()
                    Button {
                        addTier()
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
            if let error {
                Text(error)
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.negative)
                    .accessibilityIdentifier("margin-ladder-error")
            }
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
                    Text("$").font(SlabFont.mono(size: 14, weight: .semibold))
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
                    Text("%").font(SlabFont.mono(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.dim)
                }
            }
            Button {
                removeTier(row.id)
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

    private var actionStack: some View {
        VStack(spacing: Spacing.m) {
            PrimaryGoldButton(
                title: "Save ladder",
                isEnabled: storeId != nil && !tiers.isEmpty && hasChanges
            ) { save() }
                .accessibilityIdentifier("margin-ladder-save")

            Button("Reset to defaults") {
                tiers = Self.makeRows(from: .defaultMarginLadder)
                error = nil
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.muted)
            .accessibilityIdentifier("margin-ladder-reset")
        }
    }

    // MARK: - Lifecycle

    private func loadFromStore() {
        guard let userId = session.userId else { return }
        let ownerId = userId
        var descriptor = FetchDescriptor<Store>(
            predicate: #Predicate<Store> { $0.ownerUserId == ownerId }
        )
        descriptor.fetchLimit = 1
        guard let store = try? context.fetch(descriptor).first else { return }
        storeId = store.id
        let canonical = store.marginLadder.canonicalized()
        initialTiers = canonical
        tiers = Self.makeRows(from: canonical)
    }

    private var hasChanges: Bool {
        let current = tiers.compactMap(\.materialized).canonicalized()
        return current != initialTiers
    }

    private func save() {
        let materialized = tiers.compactMap(\.materialized)
        guard materialized.count == tiers.count else {
            error = "Each tier needs a comp threshold in dollars and a margin between 1% and 100%."
            return
        }
        guard !materialized.isEmpty else {
            error = "Add at least one tier."
            return
        }
        guard let storeId else {
            error = "Store not ready yet — try again in a moment."
            return
        }
        let repo = StoreSettingsRepository(
            context: context,
            kicker: kicker,
            currentStoreId: storeId
        )
        do {
            try repo.updateMarginLadder(materialized)
            initialTiers = materialized.canonicalized()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addTier() {
        // Seed a new tier just above the highest existing threshold so
        // the new row sorts predictably; defaults to 80% (mid-band) so
        // the user always sees a valid % even before they edit.
        let nextCents: Int64 = (tiers.map(\.cents).max() ?? 0) + 50_000
        tiers.insert(
            Row(id: UUID(), cents: nextCents, pct: 0.80),
            at: 0
        )
        error = nil
    }

    private func removeTier(_ id: UUID) {
        tiers.removeAll(where: { $0.id == id })
        error = nil
    }

    // MARK: - Editing row model

    /// Editing view-model row. `cents` / `pct` are the parsed numeric
    /// values; the `*Text` bindings format/parse the keypad input. A row
    /// is `materialized` only when both fields parse to in-range values.
    /// `fileprivate` (not `private`) so the same-file `Binding` extension
    /// below can reach it.
    fileprivate struct Row: Identifiable, Equatable {
        let id: UUID
        var cents: Int64
        var pct: Double

        var materialized: MarginTier? {
            guard cents >= 0, pct > 0, pct <= 1 else { return nil }
            return MarginTier(minCompCents: cents, marginPct: pct)
        }
    }

    private static func makeRows(from tiers: [MarginTier]) -> [Row] {
        tiers.canonicalized().map { Row(id: UUID(), cents: $0.minCompCents, pct: $0.marginPct) }
    }
}

// MARK: - Bindings

private extension Binding where Value == MarginLadderView.Row {
    /// Edits the cents value as a dollar amount. Strips non-digits and
    /// rejects values that overflow `Int64` cents math (huge inputs).
    var dollarsText: Binding<String> {
        Binding<String>(
            get: { String(wrappedValue.cents / 100) },
            set: { new in
                let digits = new.filter(\.isNumber)
                let dollars = Int64(digits) ?? 0
                wrappedValue.cents = dollars * 100
            }
        )
    }

    /// Edits the margin percent as an integer 0-100. The pricing math
    /// only needs cent-resolution rounding, so percentage granularity at
    /// 1% is sufficient — matches the snap density of the picker.
    var percentText: Binding<String> {
        Binding<String>(
            get: { String(Int((wrappedValue.pct * 100).rounded())) },
            set: { new in
                let digits = new.filter(\.isNumber)
                guard let pct = Int(digits) else { wrappedValue.pct = 0; return }
                // Use `Swift.min/max` to bypass `Binding`'s `@dynamicMemberLookup`
                // which would otherwise resolve bare `min`/`max` against
                // the `Row` value type and fail to find them.
                let clamped = Swift.min(Swift.max(pct, 0), 100)
                wrappedValue.pct = Double(clamped) / 100.0
            }
        )
    }
}
