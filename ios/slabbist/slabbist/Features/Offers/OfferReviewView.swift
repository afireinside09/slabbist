// Features/Offers/OfferReviewView.swift
import SwiftUI
import SwiftData

/// The "ready to present" workbench. Operator presents the offer to the vendor
/// from this screen; bounces back if they negotiate; declines if they walk;
/// "Mark paid" hands off to Plan 3's commit flow (stubbed locally here — only
/// records the `accepted` state, no transaction yet).
struct OfferReviewView: View {
    let lot: Lot
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(OutboxKicker.self) private var kicker
    @Environment(\.dismiss) private var dismiss
    @Query private var scans: [Scan]
    @State private var paymentMethod: String = "cash"
    @State private var paymentReference: String = ""
    @State private var error: String?
    @State private var isCommitting = false
    @State private var commitError: String?

    init(lot: Lot) {
        self.lot = lot
        let lotId = lot.id
        _scans = Query(filter: #Predicate<Scan> { $0.lotId == lotId },
                       sort: [SortDescriptor(\Scan.createdAt)])
    }

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    totalCard
                    linesSection
                    paymentCard
                    if let error {
                        Text(error).font(SlabFont.sans(size: 13))
                            .foregroundStyle(AppColor.negative)
                            .accessibilityIdentifier("offer-review-error")
                    }
                    actionStack
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .navigationTitle("Offer review")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: lot.lotOfferState) { _, new in
            if new == LotOfferState.paid.rawValue && isCommitting {
                isCommitting = false
                // The receipt push to TransactionDetailView happens in Plan 3 / Task 12
                // (via the lot's frozen banner). For now, dismissing this view returns to
                // the previous nav stack, and LotDetailView's frozen banner is the receipt
                // entry point.
                dismiss()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Vendor")
            Text(lot.vendorNameSnapshot ?? "No vendor attached").slabTitle()
        }
    }

    private var totalCard: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                KickerLabel("Offer total")
                Text(formattedCents(totalBuyCents)).font(SlabFont.serif(size: 40))
                Text(marginSubtitle)
                    .font(SlabFont.mono(size: 12)).foregroundStyle(AppColor.dim)
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.l)
        }
    }

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Lines")
            SlabCard {
                VStack(spacing: 0) {
                    ForEach(scans, id: \.id) { scan in
                        if scan.id != scans.first?.id { SlabCardDivider() }
                        lineRow(scan)
                    }
                }
            }
        }
    }

    private func lineRow(_ scan: Scan) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(scan.grader.rawValue) \(scan.grade ?? "—") · \(scan.certNumber)")
                    .font(SlabFont.mono(size: 12)).foregroundStyle(AppColor.muted)
            }
            Spacer()
            Text(scan.buyPriceCents.map(formattedCents) ?? "—")
                .font(SlabFont.mono(size: 14, weight: .semibold))
                .foregroundStyle(scan.buyPriceOverridden ? AppColor.gold : AppColor.text)
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
    }

    private var paymentCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Payment")
            SlabCard {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Picker("Method", selection: $paymentMethod) {
                        ForEach(["cash", "check", "store_credit", "digital", "other"], id: \.self) {
                            Text($0.replacingOccurrences(of: "_", with: " ")).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("payment-method-picker")
                    TextField("Reference (check #, Venmo handle, …)", text: $paymentReference)
                        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
                        .accessibilityIdentifier("payment-reference-field")
                }
                .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
            }
        }
    }

    private var actionStack: some View {
        VStack(spacing: Spacing.m) {
            PrimaryGoldButton(
                title: isCommitting ? "Committing…" : "Mark paid",
                isEnabled: canMarkPaid && !isCommitting
            ) {
                commit()
            }
            .accessibilityIdentifier("mark-paid")

            if let commitError {
                Text(commitError)
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.negative)
                    .accessibilityIdentifier("offer-review-commit-error")
            }

            if isCommitting && LotOfferState(rawValue: lot.lotOfferState) != .paid {
                Text("Sync pending — your offer is saved. Receipt will appear once we reach the server.")
                    .font(SlabFont.sans(size: 12)).foregroundStyle(AppColor.muted)
                    .accessibilityIdentifier("offer-review-sync-pending")
            }

            HStack(spacing: Spacing.m) {
                Button("Bounce back") {
                    do { try offerRepository().bounceBack(lot) }
                    catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.muted)
                .accessibilityIdentifier("bounce-back")
                Spacer()
                Button("Decline") {
                    do { try offerRepository().decline(lot) }
                    catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.negative)
                .accessibilityIdentifier("decline-offer")
            }
        }
    }

    /// "{N} lines · X% margin" when the lot has a manual override; "{N}
    /// lines · ladder-priced" when each scan was priced via the per-store
    /// margin ladder. Avoids surfacing a single arbitrary percentage when
    /// the underlying scans were priced at different tiers.
    private var marginSubtitle: String {
        if let pct = lot.marginPctSnapshot {
            return "\(scans.count) lines · \(Int((pct * 100).rounded()))% margin"
        }
        return "\(scans.count) lines · ladder-priced"
    }

    private var canMarkPaid: Bool {
        let state = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
        return state == .accepted || state == .presented
    }

    private func commit() {
        commitError = nil
        let repo = offerRepository()
        do {
            // If we're not yet accepted, advance to accepted first.
            if LotOfferState(rawValue: lot.lotOfferState) != .accepted {
                try repo.recordAcceptance(lot)
            }
            try repo.commit(
                lot: lot,
                paymentMethod: paymentMethod,
                paymentReference: paymentReference.isEmpty ? nil : paymentReference
            )
            isCommitting = true
        } catch {
            commitError = error.localizedDescription
        }
    }

    private var totalBuyCents: Int64 {
        scans.compactMap(\.buyPriceCents).reduce(0, +)
    }

    private func offerRepository() -> OfferRepository {
        OfferRepository(
            context: context, kicker: kicker,
            currentStoreId: lot.storeId,
            currentUserId: session.userId ?? UUID()
        )
    }

    private func formattedCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
}
