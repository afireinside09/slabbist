// Features/Vendors/VendorPicker.swift
import SwiftUI
import SwiftData

/// Sheet that lets the operator pick a vendor (or create a new one).
/// Used by Plan 2's `LotDetailView` "Attach vendor" affordance, but
/// shipped here so it can be unit-tested independently.
struct VendorPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Vendor> { $0.archivedAt == nil },
           sort: [SortDescriptor(\Vendor.displayName)])
    private var allActive: [Vendor]
    @State private var search: String = ""
    @State private var creatingNew: Bool = false

    let storeId: UUID
    let onPick: (Vendor) -> Void
    let onCreate: (UUID?, String, String?, String?, String?) throws -> Vendor

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.l) {
                topBar
                searchField
                list
                Spacer()
                newButton
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .sheet(isPresented: $creatingNew) {
            VendorEditSheet(initial: nil) { id, name, method, value, notes in
                let created = try onCreate(id, name, method, value, notes)
                onPick(created)
                dismiss()
            }
        }
    }

    private var topBar: some View {
        HStack {
            SecondaryIconButton(systemIcon: "xmark", accessibilityLabel: "Cancel") { dismiss() }
            Spacer()
        }
    }

    private var searchField: some View {
        SlabCard {
            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppColor.dim)
                TextField("Search vendors", text: $search)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("vendor-picker-search")
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
        }
    }

    /// Active vendors filtered by the search text, scoped to the store.
    /// We use client-side substring filtering because typical per-store
    /// vendor counts are <500. `pg_trgm` server-side is available if/when
    /// the directory grows past that threshold.
    private var filtered: [Vendor] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        let scoped = allActive.filter { $0.storeId == storeId }
        if trimmed.isEmpty { return scoped }
        return scoped.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
    }

    private var list: some View {
        SlabCard {
            VStack(spacing: 0) {
                if filtered.isEmpty {
                    Text(search.isEmpty ? "No vendors yet" : "No matches for \"\(search)\"")
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.dim)
                        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.l)
                } else {
                    ForEach(filtered, id: \.id) { vendor in
                        if vendor.id != filtered.first?.id { SlabCardDivider() }
                        Button {
                            onPick(vendor)
                            dismiss()
                        } label: {
                            HStack {
                                Text(vendor.displayName).slabRowTitle()
                                Spacer()
                                if let v = vendor.contactValue {
                                    Text(v).font(SlabFont.mono(size: 12))
                                        .foregroundStyle(AppColor.dim)
                                }
                            }
                            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("vendor-pick-\(vendor.displayName)")
                    }
                }
            }
        }
    }

    private var newButton: some View {
        PrimaryGoldButton(title: "+ New vendor", systemIcon: "plus") {
            creatingNew = true
        }
        .accessibilityIdentifier("vendor-picker-new")
    }
}
