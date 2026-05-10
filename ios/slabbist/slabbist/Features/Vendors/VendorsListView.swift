import SwiftUI
import SwiftData

struct VendorsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(OutboxKicker.self) private var kicker
    @State private var viewModel: VendorsViewModel?
    @State private var editingVendor: Vendor?
    @State private var presentingNew: Bool = false

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    PrimaryGoldButton(
                        title: "New vendor",
                        systemIcon: "plus",
                        isEnabled: viewModel != nil
                    ) { presentingNew = true }
                    .accessibilityIdentifier("vendor-list-new")
                    activeSection
                    archivedSection
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .navigationTitle("Vendors")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.userId) {
            viewModel = VendorsViewModel.resolve(context: context, kicker: kicker, session: session)
            viewModel?.refresh()
        }
        .sheet(isPresented: $presentingNew) {
            if let viewModel {
                VendorEditSheet(initial: nil) { id, name, method, value, notes in
                    try viewModel.upsert(id: id, displayName: name, contactMethod: method, contactValue: value, notes: notes)
                }
            }
        }
        .sheet(item: $editingVendor) { vendor in
            if let viewModel {
                VendorEditSheet(initial: vendor) { id, name, method, value, notes in
                    try viewModel.upsert(id: id, displayName: name, contactMethod: method, contactValue: value, notes: notes)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Contacts")
            Text("Vendors").slabTitle()
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        if let viewModel, !viewModel.active.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.m) {
                KickerLabel("Active")
                SlabCard {
                    VStack(spacing: 0) {
                        ForEach(viewModel.active, id: \.id) { vendor in
                            if vendor.id != viewModel.active.first?.id { SlabCardDivider() }
                            row(for: vendor)
                        }
                    }
                }
            }
        } else if viewModel != nil {
            FeatureEmptyState(
                systemImage: "person.2",
                title: "No vendors yet",
                subtitle: "Add a vendor to track buys and surface contact details when you start a lot.",
                steps: ["Tap New vendor.", "Save once and they're picker-ready forever."]
            )
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        if let viewModel, !viewModel.archived.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.m) {
                KickerLabel("Archived")
                SlabCard {
                    VStack(spacing: 0) {
                        ForEach(viewModel.archived, id: \.id) { vendor in
                            if vendor.id != viewModel.archived.first?.id { SlabCardDivider() }
                            row(for: vendor)
                        }
                    }
                }
            }
        }
    }

    private func row(for vendor: Vendor) -> some View {
        NavigationLink(value: vendor.id) {
            HStack(alignment: .center, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(vendor.displayName).slabRowTitle()
                    if let v = vendor.contactValue {
                        Text(v).font(SlabFont.mono(size: 12)).foregroundStyle(AppColor.dim)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12)).foregroundStyle(AppColor.dim)
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vendor-row-\(vendor.displayName)")
    }
}
