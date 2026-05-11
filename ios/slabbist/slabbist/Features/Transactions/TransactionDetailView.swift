import SwiftUI
import SwiftData

struct TransactionDetailView: View {
    let transaction: StoreTransaction
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(OutboxKicker.self) private var kicker
    @State private var lines: [TransactionLine] = []
    @State private var voidReason: String = ""
    @State private var showingVoidSheet: Bool = false
    @State private var voidError: String?

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    summaryCard
                    linesSection
                    if transaction.isActive {
                        voidButton
                    } else {
                        voidedBanner
                    }
                    if let voidError {
                        Text(voidError)
                            .foregroundStyle(AppColor.negative)
                            .font(SlabFont.sans(size: 13))
                            .accessibilityIdentifier("txn-void-error")
                    }
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl).padding(.vertical, Spacing.l)
            }
        }
        .navigationTitle("Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadLines() }
        .sheet(isPresented: $showingVoidSheet) { voidSheet }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Receipt")
            Text(transaction.vendorNameSnapshot).slabTitle()
            Text(formatDate(transaction.paidAt))
                .font(SlabFont.mono(size: 12)).foregroundStyle(AppColor.dim)
        }
    }

    private var summaryCard: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                KickerLabel("Total")
                Text(formatCents(transaction.totalBuyCents))
                    .font(SlabFont.serif(size: 40))
                Text("\(transaction.paymentMethod)\(transaction.paymentReference.map { " · \($0)" } ?? "")")
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
                    ForEach(lines, id: \.compositeKey) { line in
                        if line.compositeKey != lines.first?.compositeKey { SlabCardDivider() }
                        lineRow(line)
                    }
                }
            }
        }
    }

    private func lineRow(_ line: TransactionLine) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(snapshotTitle(line)).font(SlabFont.sans(size: 13))
                Text(snapshotSubtitle(line))
                    .font(SlabFont.mono(size: 11)).foregroundStyle(AppColor.dim)
            }
            Spacer()
            Text(formatCents(line.buyPriceCents))
                .font(SlabFont.mono(size: 14, weight: .semibold))
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
    }

    private var voidButton: some View {
        Button("Void transaction") { showingVoidSheet = true }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.negative)
            .accessibilityIdentifier("txn-void-button")
    }

    private var voidedBanner: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("VOIDED")
                    .font(SlabFont.mono(size: 12, weight: .semibold))
                    .tracking(1.4).foregroundStyle(AppColor.negative)
                if let r = transaction.voidReason {
                    Text(r).font(SlabFont.sans(size: 13)).foregroundStyle(AppColor.muted)
                }
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
        }
    }

    private var voidSheet: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                KickerLabel("Void")
                Text("Reason").slabTitle()
                TextField("Why are you voiding?", text: $voidReason, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("void-reason-field")
                Spacer()
                PrimaryGoldButton(title: "Confirm void", isEnabled: !voidReason.isEmpty) {
                    submitVoid()
                }
                .accessibilityIdentifier("void-confirm")
            }
            .padding(.horizontal, Spacing.xxl).padding(.vertical, Spacing.l)
        }
    }

    private func loadLines() {
        let txnId = transaction.id
        let desc = FetchDescriptor<TransactionLine>(
            predicate: #Predicate<TransactionLine> { $0.transactionId == txnId },
            sortBy: [SortDescriptor(\.lineIndex)]
        )
        lines = (try? context.fetch(desc)) ?? []
    }

    private func submitVoid() {
        let repo = OfferRepository(
            context: context, kicker: kicker,
            currentStoreId: transaction.storeId,
            currentUserId: session.userId ?? UUID()
        )
        do {
            try repo.voidTransaction(transaction, reason: voidReason)
            showingVoidSheet = false
        } catch { voidError = error.localizedDescription }
    }

    private func snapshotTitle(_ line: TransactionLine) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: line.identitySnapshotJSON) as? [String: Any] else {
            return "Line \(line.lineIndex + 1)"
        }
        let name = (json["card_name"] as? String) ?? "Line \(line.lineIndex + 1)"
        let num = (json["card_number"] as? String).map { " #\($0)" } ?? ""
        return "\(name)\(num)"
    }

    private func snapshotSubtitle(_ line: TransactionLine) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: line.identitySnapshotJSON) as? [String: Any] else { return "" }
        let parts = [
            json["set_name"] as? String,
            (json["grader"] as? String).flatMap { g in (json["grade"] as? String).map { "\(g) \($0)" } }
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    private func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: d)
    }
}
