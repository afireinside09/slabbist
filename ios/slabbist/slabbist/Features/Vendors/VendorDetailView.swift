import SwiftUI
import SwiftData

struct VendorDetailView: View {
    let vendor: Vendor
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(OutboxKicker.self) private var kicker
    @State private var viewModel: VendorsViewModel?
    @State private var editing: Bool = false
    @State private var error: String?
    @State private var history: [StoreTransaction] = []

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    contactCard
                    purchaseHistory
                    actionsCard
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .navigationTitle(vendor.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.userId) {
            viewModel = VendorsViewModel.resolve(context: context, kicker: kicker, session: session)
        }
        .sheet(isPresented: $editing) {
            if let viewModel {
                VendorEditSheet(initial: vendor) { id, name, method, value, notes in
                    try viewModel.upsert(id: id, displayName: name, contactMethod: method, contactValue: value, notes: notes)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Vendor")
            Text(vendor.displayName).slabTitle()
            if vendor.archivedAt != nil {
                Text("Archived").font(SlabFont.mono(size: 11)).foregroundStyle(AppColor.dim)
            }
        }
    }

    private var contactCard: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                KickerLabel("Contact")
                Text(vendor.contactMethod ?? "—").font(SlabFont.mono(size: 13))
                Text(vendor.contactValue ?? "no contact").font(SlabFont.sans(size: 14))
                if let notes = vendor.notes, !notes.isEmpty {
                    SlabCardDivider()
                    Text(notes).font(SlabFont.sans(size: 13)).foregroundStyle(AppColor.muted)
                }
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
        }
    }

    /// Vendor purchase history — backed by `TransactionsRepository`. Lights up
    /// after the vendor's first paid transaction; until then a soft empty state
    /// inside a SlabCard keeps the visual rhythm of the rest of the screen.
    private var purchaseHistory: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Purchase history")
            if history.isEmpty {
                SlabCard {
                    Text("No buys yet — this lights up after the vendor's first paid transaction.")
                        .font(SlabFont.sans(size: 12)).foregroundStyle(AppColor.dim)
                        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
                }
            } else {
                SlabCard {
                    VStack(spacing: 0) {
                        ForEach(history, id: \.id) { txn in
                            if txn.id != history.first?.id { SlabCardDivider() }
                            NavigationLink(destination: TransactionDetailView(transaction: txn)) {
                                historyRow(txn)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                aggregateStrip
            }
        }
        .task { loadHistory() }
    }

    private func historyRow(_ txn: StoreTransaction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(formatCents(txn.totalBuyCents))
                    .font(SlabFont.mono(size: 13, weight: .semibold))
                Text("\(txn.paymentMethod) · \(relativeDate(txn.paidAt))")
                    .font(SlabFont.mono(size: 11)).foregroundStyle(AppColor.dim)
            }
            Spacer()
            if !txn.isActive {
                Text("VOIDED")
                    .font(SlabFont.mono(size: 10, weight: .semibold))
                    .tracking(1).foregroundStyle(AppColor.negative)
            }
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
    }

    private var aggregateStrip: some View {
        HStack(spacing: Spacing.l) {
            aggregateCell(label: "Lifetime", value: formatCents(history.filter(\.isActive).reduce(0) { $0 + $1.totalBuyCents }))
            aggregateCell(label: "Last buy", value: history.first.map { relativeDate($0.paidAt) } ?? "—")
            aggregateCell(label: "Buys", value: String(history.filter(\.isActive).count))
        }
        .padding(.top, Spacing.s)
    }

    private func aggregateCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            KickerLabel(label)
            Text(value).font(SlabFont.mono(size: 13, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadHistory() {
        let repo = TransactionsRepository(
            context: context, kicker: kicker,
            currentStoreId: vendor.storeId
        )
        history = (try? repo.listForVendor(vendor.id)) ?? []
    }

    private func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private var actionsCard: some View {
        VStack(spacing: Spacing.m) {
            if let error {
                Text(error)
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.negative)
                    .accessibilityIdentifier("vendor-detail-error")
            }
            PrimaryGoldButton(title: "Edit vendor", systemIcon: "pencil") { editing = true }
                .accessibilityIdentifier("vendor-detail-edit")
            if vendor.archivedAt == nil {
                Button("Archive vendor") {
                    do {
                        try viewModel?.archive(vendor)
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.negative)
                .accessibilityIdentifier("vendor-detail-archive")
            } else {
                Button("Reactivate vendor") {
                    do {
                        try viewModel?.reactivate(vendor)
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.gold)
                .accessibilityIdentifier("vendor-detail-reactivate")
            }
        }
    }
}
