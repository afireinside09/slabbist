import Foundation
import SwiftData

@Model
final class GradedCardIdentity {
    @Attribute(.unique) var id: UUID
    var game: String
    var language: String
    var setCode: String?
    var setName: String
    var cardNumber: String?
    var cardName: String
    var variant: String?
    var year: Int?

    init(
        id: UUID,
        game: String,
        language: String,
        setCode: String? = nil,
        setName: String,
        cardNumber: String? = nil,
        cardName: String,
        variant: String? = nil,
        year: Int? = nil
    ) {
        self.id = id
        self.game = game
        self.language = language
        self.setCode = setCode
        self.setName = setName
        self.cardNumber = cardNumber
        self.cardName = cardName
        self.variant = variant
        self.year = year
    }
}
