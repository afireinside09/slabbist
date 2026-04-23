import Foundation
import Supabase

/// Thin, reusable wrapper around a single Postgrest table. Concrete
/// per-table repositories (e.g. `SupabaseLotRepository`) embed this
/// and add domain-specific query helpers on top.
///
/// Design notes:
/// - Every list query is paged by default — no unbounded fetches slip
///   in. Callers opt into full-scan semantics explicitly by passing
///   `Page.large` or composing `.next()` themselves.
/// - Callers can pass an explicit `columns` projection on reads to
///   avoid pulling heavy fields (jsonb, ocr text, photo URLs) when
///   they won't render them.
/// - Writes default to `returning: .minimal` — the server doesn't
///   echo the row back. Use `insertAndReturn` / `upsertAndReturn`
///   when you need the post-write state (server-generated defaults,
///   trigger-updated columns).
/// - All errors funnel through `SupabaseError.map(_:)` so call sites
///   catch a uniform type.
/// - Composite-key tables (e.g. `store_members`) reach for `query()`
///   to build exact filters and bypass `find(id:)` / `delete(id:)`.
///
/// For parallel fetches, callers should use `async let`:
///
///     async let stores = storeRepo.findAll()
///     async let openLots = lotRepo.list(storeId: id, status: .open)
///     let (s, l) = try await (stores, openLots)
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

    /// All rows matching the default page. For list UIs, prefer
    /// `findPage` so you can paginate; for one-shot bounded reads
    /// (e.g. lookup tables), `findAll` is fine.
    func findAll(
        page: Page = .default,
        orderBy: String? = nil,
        ascending: Bool = true,
        columns: String? = nil
    ) async throws -> [Row] {
        try await execute {
            let builder = client.from(tableName).select(columns ?? "*")
            let ordered = orderBy.map { builder.order($0, ascending: ascending) } ?? builder
            let ranged = ordered.range(from: page.range.from, to: page.range.to)
            return try await ranged.execute().value
        }
    }

    /// Page of rows plus optional total count. Total count is a
    /// separate server-side op (`count=exact` header) — opt in only
    /// when the UI actually needs it.
    func findPage(
        page: Page = .default,
        orderBy: String? = nil,
        ascending: Bool = true,
        columns: String? = nil,
        includeTotalCount: Bool = false
    ) async throws -> PagedResult<Row> {
        try await execute {
            let count: CountOption? = includeTotalCount ? .exact : nil
            let builder = client.from(tableName).select(columns ?? "*", count: count)
            let ordered = orderBy.map { builder.order($0, ascending: ascending) } ?? builder
            let ranged = ordered.range(from: page.range.from, to: page.range.to)
            let response = try await ranged.execute()
            let rows: [Row] = try response.decoded()
            return PagedResult(rows: rows, totalCount: response.count, page: page)
        }
    }

    func find(id: UUID, columns: String? = nil) async throws -> Row? {
        try await execute {
            let rows: [Row] = try await client.from(tableName)
                .select(columns ?? "*")
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first
        }
    }

    func findWhere(
        column: String,
        equals value: String,
        page: Page = .default,
        orderBy: String? = nil,
        ascending: Bool = true,
        columns: String? = nil
    ) async throws -> [Row] {
        try await execute {
            let filtered = client.from(tableName).select(columns ?? "*").eq(column, value: value)
            let ordered = orderBy.map { filtered.order($0, ascending: ascending) } ?? filtered
            let ranged = ordered.range(from: page.range.from, to: page.range.to)
            return try await ranged.execute().value
        }
    }

    func findWhere(
        column: String,
        equals value: UUID,
        page: Page = .default,
        orderBy: String? = nil,
        ascending: Bool = true,
        columns: String? = nil
    ) async throws -> [Row] {
        try await findWhere(
            column: column,
            equals: value.uuidString,
            page: page,
            orderBy: orderBy,
            ascending: ascending,
            columns: columns
        )
    }

    /// Exact row count, optionally filtered by one column equality.
    /// Cheap when there's a supporting index; expensive on large
    /// tables without one — check `EXPLAIN` before wiring into a hot
    /// path.
    func count(where column: String? = nil, equals value: String? = nil) async throws -> Int {
        try await execute {
            let selected = client.from(tableName).select("id", head: true, count: .exact)
            let filtered: PostgrestFilterBuilder
            if let column, let value {
                filtered = selected.eq(column, value: value)
            } else {
                filtered = selected
            }
            let response = try await filtered.execute()
            return response.count ?? 0
        }
    }

    // MARK: - Writes (minimal-return default)

    /// Insert without asking the server to echo the row back.
    /// Use when the client already holds the authoritative values.
    func insert(_ row: Row) async throws {
        try await execute {
            _ = try await client.from(tableName)
                .insert(row, returning: .minimal)
                .execute()
        }
    }

    func insertMany(_ rows: [Row]) async throws {
        guard !rows.isEmpty else { return }
        try await execute {
            _ = try await client.from(tableName)
                .insert(rows, returning: .minimal)
                .execute()
        }
    }

    /// Insert and return the persisted row (server-generated defaults,
    /// trigger-updated columns).
    @discardableResult
    func insertAndReturn(_ row: Row) async throws -> Row {
        try await execute {
            try await client.from(tableName)
                .insert(row, returning: .representation)
                .select()
                .single()
                .execute()
                .value
        }
    }

    func upsert(_ row: Row, onConflict: String = "id") async throws {
        try await execute {
            _ = try await client.from(tableName)
                .upsert(row, onConflict: onConflict, returning: .minimal)
                .execute()
        }
    }

    func upsertMany(_ rows: [Row], onConflict: String = "id") async throws {
        guard !rows.isEmpty else { return }
        try await execute {
            _ = try await client.from(tableName)
                .upsert(rows, onConflict: onConflict, returning: .minimal)
                .execute()
        }
    }

    @discardableResult
    func upsertAndReturn(_ row: Row, onConflict: String = "id") async throws -> Row {
        try await execute {
            try await client.from(tableName)
                .upsert(row, onConflict: onConflict, returning: .representation)
                .select()
                .single()
                .execute()
                .value
        }
    }

    func delete(id: UUID) async throws {
        try await execute {
            _ = try await client.from(tableName)
                .delete(returning: .minimal)
                .eq("id", value: id.uuidString)
                .execute()
        }
    }

    func deleteWhere(column: String, equals value: String) async throws {
        try await execute {
            _ = try await client.from(tableName)
                .delete(returning: .minimal)
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

// MARK: - Response decoding helper

private extension PostgrestResponse {
    /// Decode the response body into the requested type without going
    /// through the SDK's generic `.value` property (which requires the
    /// response's generic parameter to match).
    func decoded<U: Decodable>() throws -> U {
        try JSONCoders.decoder.decode(U.self, from: data)
    }
}
