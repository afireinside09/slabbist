import Foundation

/// Builds the PokeAPI official-artwork URL for a cameo subject from its national
/// Pokédex number. Returns `nil` when there's no `ndex` (e.g. Trainers), which
/// the row renders as a fallback icon instead of a broken image.
func cameoArtworkURL(ndex: Int?) -> URL? {
    guard let ndex else { return nil }
    return URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/\(ndex).png")
}
