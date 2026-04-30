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

    /// Active eBay listings the scraper matched to this card. Hard
    /// limit on the response (`limit`) keeps the carousel bounded.
    func ebayListings(
        productId: Int,
        subType: String,
        limit: Int
    ) async throws -> [MoverEbayListingDTO]

    /// Sets that have at least one listing in `mover_ebay_listings`.
    /// Drives the narrowed set rail on the eBay-Listings tab.
    func ebayListingsSets() async throws -> [MoversSetDTO]

    /// Flat browse-mode listings, optionally filtered. Both `priceTier`
    /// and `groupId` are orthogonal — pass `nil` to skip a filter.
    func ebayListingsBrowse(
        priceTier: MoversPriceTier?,
        groupId: Int?,
        limit: Int
    ) async throws -> [EbayListingBrowseRowDTO]
}

extension MoversRepository {
    func priceHistory(productId: Int, subType: String) async throws -> [PriceHistoryDTO] {
        try await priceHistory(productId: productId, subType: subType, days: 90)
    }

    func ebayListings(productId: Int, subType: String) async throws -> [MoverEbayListingDTO] {
        try await ebayListings(productId: productId, subType: subType, limit: 24)
    }

    func ebayListingsBrowse(
        priceTier: MoversPriceTier?,
        groupId: Int?
    ) async throws -> [EbayListingBrowseRowDTO] {
        try await ebayListingsBrowse(priceTier: priceTier, groupId: groupId, limit: 60)
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

    func ebayListings(
        productId: Int,
        subType: String = "Normal",
        limit: Int = 24
    ) async throws -> [MoverEbayListingDTO] {
        do {
            let response = try await client.rpc(
                "get_mover_ebay_listings",
                params: ListingsParams(
                    p_product_id: productId,
                    p_sub_type_name: subType,
                    p_limit: limit
                )
            ).execute()
            return try JSONCoders.decoder.decode([MoverEbayListingDTO].self, from: response.data)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    private struct HistoryParams: Encodable, Sendable {
        let p_product_id: Int
        let p_sub_type: String
        let p_days: Int
    }

    func ebayListingsSets() async throws -> [MoversSetDTO] {
        do {
            // Empty params object — RPC takes no arguments.
            let response = try await client.rpc(
                "get_ebay_listings_sets",
                params: EmptyParams()
            ).execute()
            // get_ebay_listings_sets returns `listings_count` rather
            // than `movers_count`. Decode through a thin shim and map
            // into the existing MoversSetDTO so the iOS rail is
            // schema-agnostic about which RPC fed it.
            let rows = try JSONCoders.decoder.decode([EbayListingsSetRow].self, from: response.data)
            return rows.map {
                MoversSetDTO(
                    groupId: $0.group_id,
                    groupName: $0.group_name,
                    moversCount: $0.listings_count,
                    publishedOn: $0.published_on
                )
            }
        } catch {
            throw SupabaseError.map(error)
        }
    }

    func ebayListingsBrowse(
        priceTier: MoversPriceTier?,
        groupId: Int?,
        limit: Int = 60
    ) async throws -> [EbayListingBrowseRowDTO] {
        do {
            let response = try await client.rpc(
                "get_ebay_listings",
                params: BrowseParams(
                    p_price_tier: priceTier?.rawValue,
                    p_group_id: groupId,
                    p_limit: limit
                )
            ).execute()
            return try JSONCoders.decoder.decode([EbayListingBrowseRowDTO].self, from: response.data)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    private struct ListingsParams: Encodable, Sendable {
        let p_product_id: Int
        let p_sub_type_name: String
        let p_limit: Int
    }

    private struct EmptyParams: Encodable, Sendable {}

    private struct BrowseParams: Encodable, Sendable {
        let p_price_tier: String?
        let p_group_id: Int?
        let p_limit: Int
    }

    private struct EbayListingsSetRow: Decodable, Sendable {
        let group_id: Int
        let group_name: String
        let listings_count: Int
        let published_on: Date?

        enum CodingKeys: String, CodingKey {
            case group_id, group_name, listings_count, published_on
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.group_id = try c.decode(Int.self, forKey: .group_id)
            self.group_name = try c.decode(String.self, forKey: .group_name)
            self.listings_count = try c.decode(Int.self, forKey: .listings_count)
            // Postgres `date` arrives as a yyyy-MM-dd string; tolerate it.
            if let raw = try c.decodeIfPresent(String.self, forKey: .published_on) {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone(identifier: "UTC")
                f.dateFormat = "yyyy-MM-dd"
                self.published_on = f.date(from: raw)
            } else {
                self.published_on = nil
            }
        }
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
