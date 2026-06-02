import Foundation
import SwiftUI

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

    private static let feeKey = "gradeGain.feeCents"
    private var inflight: String?

    init(repository: GradeGainRepository = SupabaseGradeGainRepository()) {
        self.repository = repository
        let saved = UserDefaults.standard.integer(forKey: Self.feeKey)
        self.feeCents = saved > 0 ? saved : 2500   // default $25
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
            catch { section = .error(String(describing: error)); return }
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
        } catch {
            guard inflight == fp else { return }
            section = .error(String(describing: error))
        }
    }

    func select(set groupId: Int) { selectedSet = groupId }
    func select(tier: MoversPriceTier) { priceTier = tier }
}
