import Foundation

/// Raised when a Postgrest DTO can't be mapped to its SwiftData
/// `@Model` counterpart — typically means the wire format drifted
/// (new enum case added server-side, unexpected null, etc.). Loud
/// by design: silent fallbacks here hide schema bugs.
nonisolated enum ModelMappingError: Error, CustomStringConvertible {
    case unknownEnumCase(type: String, value: String)
    case invalidJSON(field: String, underlying: Error)

    var description: String {
        switch self {
        case let .unknownEnumCase(type, value):
            return "Unknown \(type) case: '\(value)'"
        case let .invalidJSON(field, error):
            return "Invalid JSON in \(field): \(error.localizedDescription)"
        }
    }
}
