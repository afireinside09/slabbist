import Foundation
import Supabase

/// Thin, reusable wrapper around a single Postgrest table. Concrete
/// per-table repositories (e.g. `LotRepository`) embed this and add
/// domain-specific query helpers on top.
///
/// Everything here funnels errors through `SupabaseError.map(_:)` so
/// call sites catch a uniform type.
///
/// Composite-key tables (e.g. `store_members`) should skip `find(id:)`
/// / `deleteById` and reach for `query()` to build the exact filter
/// they need.
nonisolated struct SupabaseRepository<Row: Codable & Sendable>: Sendable {
    let tableName: String
    let client: SupabaseClient

    init(tableName: String, client: SupabaseClient = AppSupabase.shared.client) {
        self.tableName = tableName
        self.client = client
    }

    // MARK: - Escape hatch

    /// Returns the Postgrest query builder for this table. Use when the
    /// convenience methods don't cover what you need (compound filters,
    /// composite keys, `.in`, `.is`, joins, RPC-style selects, etc.).
    func query() -> PostgrestQueryBuilder {
        client.from(tableName)
    }

    // MARK: - Reads

    func findAll() async throws -> [Row] {
        try await execute { try await client.from(tableName).select().execute().value }
    }

    func findAll(orderBy column: String, ascending: Bool = true) async throws -> [Row] {
        try await execute {
            try await client.from(tableName)
                .select()
                .order(column, ascending: ascending)
                .execute()
                .value
        }
    }

    func find(id: UUID) async throws -> Row? {
        try await execute {
            let rows: [Row] = try await client.from(tableName)
                .select()
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first
        }
    }

    func findWhere(column: String, equals value: String) async throws -> [Row] {
        try await execute {
            try await client.from(tableName)
                .select()
                .eq(column, value: value)
                .execute()
                .value
        }
    }

    func findWhere(column: String, equals value: UUID) async throws -> [Row] {
        try await findWhere(column: column, equals: value.uuidString)
    }

    // MARK: - Writes

    @discardableResult
    func insert(_ row: Row) async throws -> Row {
        try await execute {
            try await client.from(tableName)
                .insert(row)
                .select()
                .single()
                .execute()
                .value
        }
    }

    @discardableResult
    func insertMany(_ rows: [Row]) async throws -> [Row] {
        guard !rows.isEmpty else { return [] }
        return try await execute {
            try await client.from(tableName)
                .insert(rows)
                .select()
                .execute()
                .value
        }
    }

    @discardableResult
    func upsert(_ row: Row, onConflict: String = "id") async throws -> Row {
        try await execute {
            try await client.from(tableName)
                .upsert(row, onConflict: onConflict)
                .select()
                .single()
                .execute()
                .value
        }
    }

    @discardableResult
    func upsertMany(_ rows: [Row], onConflict: String = "id") async throws -> [Row] {
        guard !rows.isEmpty else { return [] }
        return try await execute {
            try await client.from(tableName)
                .upsert(rows, onConflict: onConflict)
                .select()
                .execute()
                .value
        }
    }

    func delete(id: UUID) async throws {
        try await execute {
            _ = try await client.from(tableName)
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        }
    }

    func deleteWhere(column: String, equals value: String) async throws {
        try await execute {
            _ = try await client.from(tableName)
                .delete()
                .eq(column, value: value)
                .execute()
        }
    }

    // MARK: - Error funnel

    private func execute<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw SupabaseError.map(error)
        }
    }
}
