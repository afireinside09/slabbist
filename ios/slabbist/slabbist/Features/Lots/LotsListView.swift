import SwiftUI
import SwiftData
import OSLog

struct LotsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session

    @State private var showingNewLot = false
    @State private var lots: [Lot] = []
    @State private var selectedLot: Lot?
    @State private var viewModel: LotsViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if lots.isEmpty {
                    emptyState
                } else {
                    List(lots) { lot in
                        Button {
                            selectedLot = lot
                        } label: {
                            row(for: lot)
                        }
                    }
                }
            }
            .navigationTitle("Lots")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewLot = true
                    } label: {
                        Label("New bulk scan", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewLot) {
                if let viewModel {
                    NewLotSheet { name in
                        let lot = try viewModel.createLot(name: name)
                        refresh()
                        selectedLot = lot
                    }
                }
            }
            .navigationDestination(item: $selectedLot) { lot in
                BulkScanView(lot: lot)
            }
            .onAppear {
                bootstrapViewModel()
                refresh()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No lots yet").font(.title3.weight(.semibold))
            Text("Start your first bulk scan to see it here.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("New bulk scan") { showingNewLot = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(Spacing.xl)
    }

    private func row(for lot: Lot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(lot.name).font(.headline)
            HStack {
                Text(lot.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(lot.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bootstrapViewModel() {
        guard viewModel == nil else { return }
        guard let userId = session.userId else { return }

        // Plan 1 MVP: single store per user. Fetch the first store the user owns.
        let ownerId = userId
        var descriptor = FetchDescriptor<Store>(
            predicate: #Predicate<Store> { $0.ownerUserId == ownerId }
        )
        descriptor.fetchLimit = 1

        if let store = try? context.fetch(descriptor).first {
            viewModel = LotsViewModel(context: context, currentUserId: userId, currentStoreId: store.id)
        } else {
            // Store row hasn't synced yet. For Plan 1, fall back to a placeholder;
            // Plan 2 introduces a store-fetch sync on session establishment.
            AppLog.lots.warning("no local Store for user \(userId, privacy: .public); view model deferred")
        }
    }

    private func refresh() {
        guard let viewModel else {
            lots = []
            return
        }
        do {
            lots = try viewModel.listOpenLots()
        } catch {
            AppLog.lots.error("listOpenLots failed: \(error.localizedDescription, privacy: .public)")
            lots = []
        }
    }
}
