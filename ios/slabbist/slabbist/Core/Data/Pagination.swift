import Foundation

/// Offset-based page descriptor. Used by every list query in the
/// data layer so we never fall into an unbounded fetch.
///
/// Callers that need higher throughput on hot paths should prefer
/// keyset pagination (an `.gt("created_at", lastSeen)` filter plus
/// `Page.first(n)`) — it stays O(log n) as the table grows.
nonisolated struct Page: Sendable, Equatable {
    var limit: Int
    var offset: Int

    static let `default` = Page(limit: 50, offset: 0)
    static let small = Page(limit: 20, offset: 0)
    static let large = Page(limit: 200, offset: 0)

    static func first(_ limit: Int) -> Page {
        Page(limit: limit, offset: 0)
    }

    /// Next contiguous page of the same size.
    func next() -> Page {
        Page(limit: limit, offset: offset + limit)
    }

    /// Half-open Postgrest range: `[offset, offset + limit - 1]`.
    var range: (from: Int, to: Int) {
        (from: offset, to: offset + max(limit, 1) - 1)
    }
}

/// A page of rows, optionally with a total count.
nonisolated struct PagedResult<Row: Sendable>: Sendable {
    var rows: [Row]
    /// Total row count across all pages — populated only if the caller
    /// opted in via `includeTotalCount`. Server computes this with the
    /// Postgrest `count=exact` header.
    var totalCount: Int?
    /// The page descriptor used to fetch these rows — handy for
    /// composing `.next()`.
    var page: Page

    /// Heuristic: if we got back a full page, assume there may be more.
    /// Authoritative only when `totalCount` is set.
    var hasMore: Bool {
        if let totalCount {
            return page.offset + rows.count < totalCount
        }
        return rows.count == page.limit
    }
}
