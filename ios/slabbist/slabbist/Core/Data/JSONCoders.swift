import Foundation

/// Process-wide JSON encoder / decoder cache. Allocating a
/// `JSONEncoder` costs real CPU (it sets up date / data / key
/// strategies each time), and the mapping layer ran one per row on
/// the hot paths. A shared instance is safe because `JSONEncoder` /
/// `JSONDecoder` are thread-safe once configured in Swift 6+.
nonisolated enum JSONCoders {
    /// Encoder used for outbound Postgrest payloads *produced outside*
    /// the Supabase SDK (the SDK has its own configured encoder for
    /// requests). Primarily used by the DTO↔@Model mapping layer.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Mirror decoder for symmetry with `encoder`.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
