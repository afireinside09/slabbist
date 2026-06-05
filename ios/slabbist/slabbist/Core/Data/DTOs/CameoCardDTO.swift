import Foundation

/// One row from `public.cameo_cards` — a card (or reprint) featuring a cameo
/// subject. `cardNumber`/`notes` are nullable in Postgres.
nonisolated struct CameoCardDTO: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: UUID
    let subjectId: UUID
    let cardName: String
    let setName: String
    let cardNumber: String?
    let notes: String?
    let generation: String

    enum CodingKeys: String, CodingKey {
        case id
        case subjectId  = "subject_id"
        case cardName   = "card_name"
        case setName    = "set_name"
        case cardNumber = "card_number"
        case notes, generation
    }
}
