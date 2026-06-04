import Foundation
import SwiftUI
import SwiftData

@Observable
@MainActor
final class GradeGainViewModel {
    private let repository: GradeGainRepository

    var sets: [GradeGainSetDTO] = []
    var selectedSet: Int?
    var priceTier: MoversPriceTier = .under5
    /// User-adjustable grading fee in cents. Persisted across launches.
    var feeCents: Int {
        didSet { UserDefaults.standard.set(feeCents, forKey: Self.feeKey) }
    }
    var section: GradeGainSection = .idle

    /// True when `section` is showing the persisted last-known-good rows
    /// because the live fetch failed (offline). Drives the "as of <time>"
    /// stale banner so the operator knows the data isn't fresh.
    private(set) var isStale = false
    private(set) var staleFetchedAt: Date?
    private(set) var staleContextLabel: String?

    private static let feeKey = "gradeGain.feeCents"
    private var inflight: String?

    /// SwiftData context for the last-known-good cache. Injected by the
    /// view (`attach(_:)`) since the VM is constructed before the
    /// environment context is available. Nil in unit tests → caching no-ops.
    private var modelContext: ModelContext?

    init(repository: GradeGainRepository = SupabaseGradeGainRepository()) {
        self.repository = repository
        let saved = UserDefaults.standard.integer(forKey: Self.feeKey)
        self.feeCents = saved > 0 ? saved : 2500   // default $25
    }

    /// Wire the SwiftData context used for the offline cache. Idempotent.
    func attach(_ context: ModelContext) {
        if modelContext == nil { modelContext = context }
    }

    /// Rows that remain profitable after the current fee, server-sorted by
    /// spread (so the fee, a constant, preserves order).
    var visibleRows: [GradeGainDTO] {
        guard case let .loaded(rows) = section else { return [] }
        return rows.filter { $0.profitCents(feeCents: feeCents) > 0 }
    }

    private var fingerprint: String { "\(selectedSet.map(String.init) ?? "nil")|\(priceTier.rawValue)" }

    func load() async {
        if sets.isEmpty {
            do { sets = try await repository.sets() }
            catch {
                // Sets fetch failed (likely offline) — fall back to the last
                // good gains we cached, or surface the error if there's none.
                restoreFromSnapshot(orElse: { section = .error(error.localizedDescription) })
                return
            }
        }
        if selectedSet == nil {
            // Newest set by release date. The RPC already orders newest-first,
            // but selecting on publishedOn explicitly makes the intent (and the
            // test) independent of server ordering.
            selectedSet = sets.max(by: { ($0.publishedOn ?? .distantPast) < ($1.publishedOn ?? .distantPast) })?.groupId
                ?? sets.first?.groupId
        }
        guard let group = selectedSet else { section = .loaded([]); return }

        let fp = fingerprint
        inflight = fp
        section = .loading
        do {
            let rows = try await repository.setGains(groupId: group, priceTier: priceTier)
            guard inflight == fp else { return }   // a newer filter superseded this fetch
            section = .loaded(rows)
            isStale = false
            saveSnapshot(rows: rows, group: group)
        } catch {
            guard inflight == fp else { return }
            restoreFromSnapshot(orElse: { section = .error(error.localizedDescription) })
        }
    }

    func select(set groupId: Int) { selectedSet = groupId }
    func select(tier: MoversPriceTier) { priceTier = tier }

    // MARK: - Last-known-good cache

    /// A live fetch failed: show the persisted rows labeled stale, or run
    /// `orElse` (surface the error) when there's nothing cached.
    private func restoreFromSnapshot(orElse: () -> Void) {
        guard
            let context = modelContext,
            let snap = try? context.fetch(snapshotDescriptor()).first,
            let rows = try? JSONCoders.decoder.decode([GradeGainDTO].self, from: snap.payload)
        else {
            orElse()
            return
        }
        section = .loaded(rows)
        isStale = true
        staleFetchedAt = snap.fetchedAt
        staleContextLabel = snap.contextLabel
    }

    /// Persist the latest successful result as the single last-known-good row.
    private func saveSnapshot(rows: [GradeGainDTO], group: Int) {
        guard
            let context = modelContext,
            let payload = try? JSONCoders.encoder.encode(rows)
        else { return }
        let label = contextLabel(group: group)
        if let existing = try? context.fetch(snapshotDescriptor()).first {
            existing.payload = payload
            existing.contextLabel = label
            existing.fetchedAt = Date()
        } else {
            context.insert(GradeGainSnapshot(payload: payload, contextLabel: label, fetchedAt: Date()))
        }
        try? context.save()
    }

    private func snapshotDescriptor() -> FetchDescriptor<GradeGainSnapshot> {
        let id = GradeGainSnapshot.singletonID
        var d = FetchDescriptor<GradeGainSnapshot>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return d
    }

    private func contextLabel(group: Int) -> String {
        let setName = sets.first { $0.groupId == group }?.groupName ?? "Set \(group)"
        return "\(setName) · \(priceTier.displayName)"
    }
}
