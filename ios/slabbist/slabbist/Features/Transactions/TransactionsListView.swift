import SwiftUI
import SwiftData

struct TransactionsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Query(sort: [SortDescriptor(\StoreTransaction.paidAt, order: .reverse)])
    private var transactions: [StoreTransaction]

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    KickerLabel("Ledger")
                    Text("Transactions").slabTitle()
                    if transactions.isEmpty {
                        FeatureEmptyState(
                            systemImage: "list.bullet.rectangle",
                            title: "No transactions yet",
                            subtitle: "Once you mark a lot paid, the receipt lands here.",
                            steps: []
                        )
                    } else {
                        SlabCard {
                            VStack(spacing: 0) {
                                ForEach(transactions, id: \.id) { txn in
                                    if txn.id != transactions.first?.id { SlabCardDivider() }
                                    NavigationLink(value: txn.id) {
                                        row(for: txn)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("txn-row-\(txn.id.uuidString)")
                                }
                            }
                        }
                    }
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl).padding(.vertical, Spacing.l)
            }
        }
        .navigationTitle("Transactions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for txn: StoreTransaction) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack {
                    Text(txn.vendorNameSnapshot).slabRowTitle()
                    if !txn.isActive {
                        Text(txn.voidedAt != nil ? "VOIDED" : "VOID")
                            .font(SlabFont.mono(size: 10, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(AppColor.negative)
                    }
                }
                Text("\(formatCents(txn.totalBuyCents)) · \(txn.paymentMethod)")
                    .font(SlabFont.mono(size: 12)).foregroundStyle(AppColor.dim)
            }
            Spacer()
            Text(relativeDate(txn.paidAt))
                .font(SlabFont.mono(size: 11)).foregroundStyle(AppColor.dim)
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
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
}
