import SwiftUI

/// Sheet for editing the store's buy price on a single slab. Mirrors
/// `ManualPriceSheet` in shape and parsing semantics but writes to
/// `Scan.buyPriceCents` via `OfferRepository.setBuyPrice(... overridden: true)`.
/// Numeric-only entry, "12.34" normalizes to 1234 cents on submit. Clearing
/// hands `nil` to the caller so the auto-derived value can take over again
/// the next time the comp lands or the lot margin changes.
struct BuyPriceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    @State private var error: String?
    @FocusState private var fieldFocused: Bool

    let initialCents: Int64?
    let onSubmit: (Int64?) throws -> Void

    init(initialCents: Int64?, onSubmit: @escaping (Int64?) throws -> Void) {
        self.initialCents = initialCents
        self.onSubmit = onSubmit
        // Pre-fill with the existing buy price (if any) in dollars.cents form so
        // the user can adjust an existing entry without retyping from zero.
        if let cents = initialCents {
            let dollars = Double(cents) / 100
            _input = State(initialValue: Self.formatter.string(from: dollars as NSNumber) ?? "")
        } else {
            _input = State(initialValue: "")
        }
    }

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                topBar
                header
                priceCard
                if let error {
                    Text(error)
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.negative)
                        .accessibilityIdentifier("buy-price-error")
                }
                Spacer()
                if initialCents != nil {
                    Button(action: clear) {
                        Text("Reset to auto")
                            .font(SlabFont.sans(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                                    .stroke(AppColor.hairlineStrong, lineWidth: 1)
                            )
                            .foregroundStyle(AppColor.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("buy-price-clear")
                }
                PrimaryGoldButton(
                    title: initialCents == nil ? "Save buy price" : "Update buy price",
                    isEnabled: !trimmed.isEmpty
                ) {
                    submit()
                }
                .accessibilityIdentifier("buy-price-save")
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .onAppear { fieldFocused = true }
    }

    private var topBar: some View {
        HStack {
            SecondaryIconButton(systemIcon: "xmark", accessibilityLabel: "Cancel") {
                dismiss()
            }
            Spacer()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Buy price")
            Text("Adjust the store's offer for this slab").slabTitle()
            Text("Override the auto-derived buy price. Clear to fall back to the lot's margin rule the next time the comp updates.")
                .font(SlabFont.sans(size: 13))
                .foregroundStyle(AppColor.muted)
        }
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Buy price (USD)")
            SlabCard {
                HStack(spacing: Spacing.m) {
                    Text("$")
                        .font(SlabFont.mono(size: 20, weight: .semibold))
                        .foregroundStyle(AppColor.gold)
                        .frame(width: 18)
                    TextField(
                        "",
                        text: $input,
                        prompt: Text("0.00").foregroundStyle(AppColor.dim)
                    )
                    .keyboardType(.decimalPad)
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .onSubmit { submit() }
                    .foregroundStyle(AppColor.text)
                    .tint(AppColor.gold)
                    .font(SlabFont.mono(size: 20, weight: .semibold))
                    .accessibilityIdentifier("buy-price-field")
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.md)
            }
        }
    }

    private var trimmed: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseCents(_ raw: String) -> Int64? {
        // Strip currency symbols + thousands separators users sometimes paste.
        // Accept both "." and "," as the decimal mark — most US users type
        // ".", but pasted values from spreadsheets sometimes carry ",".
        let cleaned = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty, let dollars = Double(cleaned), dollars >= 0 else {
            return nil
        }
        // Round-half-up to the nearest cent so 12.345 → 1235, not 1234.
        let cents = Int64((dollars * 100).rounded())
        return cents
    }

    private func submit() {
        let raw = trimmed
        guard !raw.isEmpty else { return }
        guard let cents = parseCents(raw) else {
            error = "Enter a price in dollars (e.g. 49.99)."
            return
        }
        do {
            try onSubmit(cents)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func clear() {
        do {
            try onSubmit(nil)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = false
        return f
    }()
}

#Preview("New") {
    BuyPriceSheet(initialCents: nil) { _ in }
}

#Preview("Existing") {
    BuyPriceSheet(initialCents: 12_99) { _ in }
}
