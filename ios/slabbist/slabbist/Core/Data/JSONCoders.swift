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
    ///
    /// Uses a custom date strategy because PostgREST emits timestamptz
    /// with fractional seconds (e.g. `2026-04-28T20:51:39.5+00:00`) for
    /// any column whose source data has sub-second precision, but the
    /// stock `.iso8601` strategy only accepts the no-fraction form.
    /// Trying fractional first and falling back to the basic formatter
    /// covers both shapes without changing wire formats elsewhere.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = isoFractional.date(from: raw) { return date }
            if let date = isoBasic.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Expected ISO 8601 date, got \(raw)")
            )
        }
        return decoder
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
