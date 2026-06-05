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
    /// PostgREST embed of the mapped TCGplayer product (`tcg_products`); nil when
    /// the card has no `tcgplayer_product_id` yet.
    let tcgProduct: CameoCardProductDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case subjectId  = "subject_id"
        case cardName   = "card_name"
        case setName    = "set_name"
        case cardNumber = "card_number"
        case notes, generation
        case tcgProduct = "tcg_products"
    }
}

/// The subset of `public.tcg_products` embedded alongside a cameo card — enough
/// to render the image and a product-specific affiliate link.
nonisolated struct CameoCardProductDTO: Codable, Sendable, Equatable, Hashable {
    let productId: Int
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case imageURL  = "image_url"
    }
}
