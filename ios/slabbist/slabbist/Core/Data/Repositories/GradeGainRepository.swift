import Foundation
import Supabase

protocol GradeGainRepository: Sendable {
    func sets() async throws -> [GradeGainSetDTO]
    func setGains(groupId: Int, priceTier: MoversPriceTier) async throws -> [GradeGainDTO]
}

nonisolated struct SupabaseGradeGainRepository: GradeGainRepository, Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
    }

    func sets() async throws -> [GradeGainSetDTO] {
        do {
            // Empty params object — RPC takes no arguments.
            let response = try await client.rpc(
                "get_grade_gain_sets",
                params: NoParams()
            ).execute()
            return try JSONCoders.decoder.decode([GradeGainSetDTO].self, from: response.data)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    func setGains(groupId: Int, priceTier: MoversPriceTier) async throws -> [GradeGainDTO] {
        do {
            let response = try await client.rpc(
                "get_set_grade_gains",
                params: SetGainsParams(p_group_id: groupId, p_price_tier: priceTier.rawValue)
            ).execute()
            return try JSONCoders.decoder.decode([GradeGainDTO].self, from: response.data)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    private struct NoParams: Encodable, Sendable {}

    private struct SetGainsParams: Encodable, Sendable { let p_group_id: Int; let p_price_tier: String }
}
