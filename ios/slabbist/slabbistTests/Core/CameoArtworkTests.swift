import Foundation
import Testing
@testable import slabbist

@Suite("Cameo artwork URL")
struct CameoArtworkTests {
    // Why: each Pokémon row builds its thumbnail source purely from the ndex it
    // already carries. A wrong path means every artwork silently 404s and the
    // list looks broken — so pin the exact PokeAPI official-artwork URL.
    @Test("pokemon ndex maps to the PokeAPI official-artwork URL")
    func pokemon() {
        #expect(
            cameoArtworkURL(ndex: 25)
                == URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/25.png")
        )
    }

    // Why: trainers have no ndex; they must degrade to the fallback icon rather
    // than request a malformed URL.
    @Test("nil ndex yields no URL")
    func trainer() {
        #expect(cameoArtworkURL(ndex: nil) == nil)
    }
}
