import Foundation

/// One row from `public.cameo_subjects` — a Pokémon or Trainer that appears as
/// a cameo on TCG cards. `ndex` is set for pokemon, `region` for trainers.
nonisolated struct CameoSubjectDTO: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: UUID
    let kind: String
    let ndex: Int?
    let region: String?
    let name: String
    let cardCount: Int

    enum CodingKeys: String, CodingKey {
        case id, kind, ndex, region, name
        case cardCount = "card_count"
    }
}
