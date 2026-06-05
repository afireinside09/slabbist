import Foundation
import Testing
@testable import slabbist

@Suite("Cameo DTO decode")
struct CameoDTODecodeTests {
    // Why: the secret screen renders straight from PostgREST rows, so the DTOs
    // must round-trip the exact snake_case shape — including null ndex/region
    // (trainers) and null card_number/notes — or rows silently drop.
    @Test("subject decodes pokemon and trainer shapes")
    func subject() throws {
        let json = """
        [
          {"id":"22222222-2222-2222-2222-222222222222","kind":"pokemon","ndex":25,"region":null,"name":"Pikachu","card_count":42},
          {"id":"33333333-3333-3333-3333-333333333333","kind":"trainer","ndex":null,"region":"KANTO","name":"Red","card_count":7}
        ]
        """.data(using: .utf8)!
        let rows = try JSONDecoder().decode([CameoSubjectDTO].self, from: json)
        #expect(rows[0].ndex == 25)
        #expect(rows[0].region == nil)
        #expect(rows[1].ndex == nil)
        #expect(rows[1].region == "KANTO")
        #expect(rows[1].name == "Red")
    }

    @Test("card decodes with null card_number and notes")
    func card() throws {
        let json = """
        [{"id":"44444444-4444-4444-4444-444444444444","subject_id":"22222222-2222-2222-2222-222222222222",
          "card_name":"Pokémon March","set_name":"Neo Genesis","card_number":null,"notes":null,"generation":"Gen 2"}]
        """.data(using: .utf8)!
        let rows = try JSONDecoder().decode([CameoCardDTO].self, from: json)
        #expect(rows[0].cardName == "Pokémon March")
        #expect(rows[0].cardNumber == nil)
        #expect(rows[0].notes == nil)
    }
}
