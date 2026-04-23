import Foundation
import Supabase

/// Reads the `public.get_top_movers` RPC. One call returns up to N
/// pre-ordered movers for a category + direction, so the UI issues a
/// single round-trip per tab switch.
///
/// The RPC is intentionally the only entry point here — there is no
/// "list all price history" surface, because scanning raw history from
/// the client would skip the server-side index-only plan.
protocol MoversRepository: Sendable {
    func topMovers(
        language: MoversLanguage,
        direction: MoversDirection,
        limit: Int,
        subType: String
    ) async throws -> [MoverDTO]
}

extension MoversRepository {
    func topMovers(
        language: MoversLanguage,
        direction: MoversDirection
    ) async throws -> [MoverDTO] {
        try await topMovers(language: language, direction: direction, limit: 10, subType: "Normal")
    }
}

nonisolated struct SupabaseMoversRepository: MoversRepository, Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
    }

    func topMovers(
        language: MoversLanguage,
        direction: MoversDirection,
        limit: Int = 10,
        subType: String = "Normal"
    ) async throws -> [MoverDTO] {
        do {
            let response = try await client.rpc(
                "get_top_movers",
                params: Params(
                    p_category_id: language.rawValue,
                    p_direction: direction.rawValue,
                    p_limit: limit,
                    p_sub_type: subType
                )
            ).execute()
            return try JSONCoders.decoder.decode([MoverDTO].self, from: response.data)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    /// Snake-cased to match the Postgres function parameter names —
    /// Postgrest maps these straight through.
    private struct Params: Encodable, Sendable {
        let p_category_id: Int
        let p_direction: String
        let p_limit: Int
        let p_sub_type: String
    }
}
