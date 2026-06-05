import Foundation
import Supabase

/// Reads the global-reference cameo tables PostgREST-direct (public-read RLS).
/// Not the aggregator/proxy hero-flow, so no edge function — same direct-query
/// pattern as `SupabaseStoreMemberRepository`.
nonisolated struct CameoRepository: Sendable {
    private let subjects: SupabaseRepository<CameoSubjectDTO>
    private let cards: SupabaseRepository<CameoCardDTO>

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.subjects = SupabaseRepository(tableName: "cameo_subjects", client: client)
        self.cards = SupabaseRepository(tableName: "cameo_cards", client: client)
    }

    /// Subjects whose name matches `query` (case-insensitive substring). A blank
    /// query returns the full list. Ordered by ndex (trainers, ndex null, sort
    /// last) then name. Capped at 1000 — the dataset is ~3k but a single screen
    /// never needs more; search narrows it.
    func searchSubjects(_ query: String) async throws -> [CameoSubjectDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            var builder = subjects.query().select()
            if !trimmed.isEmpty {
                builder = builder.ilike("name", pattern: "%\(trimmed)%")
            }
            return try await builder
                .order("ndex", ascending: true, nullsFirst: false)
                .order("name", ascending: true)
                .limit(1000)
                .execute()
                .value
        } catch {
            throw SupabaseError.map(error)
        }
    }

    /// Every card (incl. reprints) for one subject, grouped by generation then set.
    func cards(forSubject id: UUID) async throws -> [CameoCardDTO] {
        do {
            return try await cards.query()
                .select("*, tcg_products(product_id, image_url)")
                .eq("subject_id", value: id.uuidString)
                .order("generation", ascending: true)
                .order("set_name", ascending: true)
                .execute()
                .value
        } catch {
            throw SupabaseError.map(error)
        }
    }
}
