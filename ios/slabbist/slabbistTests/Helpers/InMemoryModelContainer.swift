import Foundation
import SwiftData
@testable import slabbist

/// Builds a SwiftData `ModelContainer` backed by an in-memory store.
///
/// Keep the schema minimal — only register `@Model` types the tests actually
/// touch. Add more types here when a new compile error demands one; the
/// container otherwise stays as small (and cheap) as possible.
@MainActor
enum InMemoryModelContainer {
    /// In-memory container with the comp-fetch-relevant model graph
    /// (`Scan` + `GradedMarketSnapshot`). Tests that need additional
    /// `@Model` types should call `make(for:)` with a custom list.
    static func make() throws -> ModelContainer {
        try make(for: [Scan.self, GradedMarketSnapshot.self])
    }

    /// In-memory container for an arbitrary set of `@Model` types.
    static func make(for types: [any PersistentModel.Type]) throws -> ModelContainer {
        let schema = Schema(types)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
