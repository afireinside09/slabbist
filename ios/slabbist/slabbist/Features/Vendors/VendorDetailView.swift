import SwiftUI
import SwiftData

struct VendorDetailView: View {
    let vendor: Vendor
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(OutboxKicker.self) private var kicker
    @State private var viewModel: VendorsViewModel?
    @State private var editing: Bool = false

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    contactCard
                    purchaseHistoryStub
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

    /// Plan 3 fills this with the actual transaction list. Kept stubbed so
    /// the UI shape is settled and the empty state copy is locked in.
    private var purchaseHistoryStub: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                KickerLabel("Purchase history")
                Text("No buys yet — purchase history lights up after this vendor's first paid transaction.")
                    .font(SlabFont.sans(size: 12)).foregroundStyle(AppColor.dim)
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
        }
    }

    private var actionsCard: some View {
        VStack(spacing: Spacing.m) {
            PrimaryGoldButton(title: "Edit vendor", systemIcon: "pencil") { editing = true }
                .accessibilityIdentifier("vendor-detail-edit")
            if vendor.archivedAt == nil {
                Button("Archive vendor") {
                    try? viewModel?.archive(vendor)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.negative)
                .accessibilityIdentifier("vendor-detail-archive")
            } else {
                Button("Reactivate vendor") {
                    try? viewModel?.reactivate(vendor)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.gold)
                .accessibilityIdentifier("vendor-detail-reactivate")
            }
        }
    }
}
