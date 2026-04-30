import Foundation
import Supabase

/// Reads the movers RPCs.
///
///   - `topMovers(language:direction:limit:priceTier:)`
///       → `get_top_movers(category_id, direction, limit, price_tier)`
///       Category-wide top-N for a language + tier. Reserved for
///       future "all sets" surfaces; the iOS Movers tab doesn't call
///       this today (it always picks a specific set).
///
///   - `sets(language:)`
///       → `get_movers_sets(category_id)`
///       Every set with at least one mover, regardless of tier or
///       sub-type. The set rail is a navigational concept that
///       should stay stable across both axes.
///
///   - `setMovers(groupId:priceTier:)`
///       → `get_set_movers(group_id, price_tier)`
///       Both directions for a single set + tier in one call. The
///       slate now spans every sub-type (Normal, Holofoil, etc.) —
///       sub_type_name comes through as descriptive metadata on each
///       row. Caller splits by `MoverDTO.direction`.
///
///   - `priceHistory(productId:subType:days:)`
///       → `get_product_price_history(product_id, sub_type, days)`
///       Time-series points for the detail screen's chart. This RPC
///       *does* take a sub-type because the detail screen is scoped
///       to one (product, variant) pair.
protocol MoversRepository: Sendable {
    func topMovers(
        language: MoversLanguage,
        direction: MoversDirection,
        limit: Int,
        priceTier: MoversPriceTier
    ) async throws -> [MoverDTO]

    func sets(
        language: MoversLanguage
    ) async throws -> [MoversSetDTO]

    func setMovers(
        groupId: Int,
        priceTier: MoversPriceTier
    ) async throws -> [MoverDTO]

    func priceHistory(
        productId: Int,
        subType: String,
        days: Int
    ) async throws -> [PriceHistoryDTO]
}

extension MoversRepository {
    func priceHistory(productId: Int, subType: String) async throws -> [PriceHistoryDTO] {
        try await priceHistory(productId: productId, subType: subType, days: 90)
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
        limit: Int,
        priceTier: MoversPriceTier
    ) async throws -> [MoverDTO] {
        do {
            let response = try await client.rpc(
                "get_top_movers",
                params: TopParams(
                    p_category_id: language.rawValue,
                    p_direction: direction.rawValue,
                    p_limit: limit,
                    p_price_tier: priceTier.rawValue
                )
            ).execute()
            return try JSONCoders.decoder.decode([MoverDTO].self, from: response.data)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    func sets(
        language: MoversLanguage
    ) async throws -> [MoversSetDTO] {
        do {
            let response = try await client.rpc(
                "get_movers_sets",
                params: SetsParams(p_category_id: language.rawValue)
            ).execute()
            return try JSONCoders.decoder.decode([MoversSetDTO].self, from: response.data)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    func setMovers(
        groupId: Int,
        priceTier: MoversPriceTier
    ) async throws -> [MoverDTO] {
        do {
            let response = try await client.rpc(
                "get_set_movers",
                params: SetMoversParams(
                    p_group_id: groupId,
                    p_price_tier: priceTier.rawValue
                )
            ).execute()
            return try JSONCoders.decoder.decode([MoverDTO].self, from: response.data)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    func priceHistory(
        productId: Int,
        subType: String = "Normal",
        days: Int = 90
    ) async throws -> [PriceHistoryDTO] {
        do {
            let response = try await client.rpc(
                "get_product_price_history",
                params: HistoryParams(
                    p_product_id: productId,
                    p_sub_type: subType,
                    p_days: days
                )
            ).execute()
            return try JSONCoders.decoder.decode([PriceHistoryDTO].self, from: response.data)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    private struct HistoryParams: Encodable, Sendable {
        let p_product_id: Int
        let p_sub_type: String
        let p_days: Int
    }

    private struct TopParams: Encodable, Sendable {
        let p_category_id: Int
        let p_direction: String
        let p_limit: Int
        let p_price_tier: String
    }

    private struct SetsParams: Encodable, Sendable {
        let p_category_id: Int
    }

    private struct SetMoversParams: Encodable, Sendable {
        let p_group_id: Int
        let p_price_tier: String
    }
}
