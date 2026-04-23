import Foundation
import Testing
import Supabase
@testable import slabbist

/// Verify that concrete repositories emit the exact Postgrest filter
/// URLs we expect. Uses `CapturingURLProtocol` so no network is
/// involved. When adding new repository methods, add a case here —
/// this is the tripwire that catches accidental changes to the wire
/// contract (column names, sort order, filter operator, pagination).
@Suite("Query Construction", .serialized)
struct QueryConstructionTests {
    private func makeClient() -> SupabaseClient {
        let session = CapturingURLProtocol.makeSession()
        return SupabaseClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "test-anon-key",
            options: SupabaseClientOptions(
                global: .init(session: session)
            )
        )
    }

    @Test("LotRepository.listItems emits store_id filter, created_at desc, slim projection, and Range header")
    func lotListItems() async throws {
        CapturingURLProtocol.reset()
        let client = makeClient()
        let repo = SupabaseLotRepository(client: client)
        let storeId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        _ = try await repo.listItems(
            storeId: storeId,
            status: nil,
            page: Page(limit: 25, offset: 50),
            includeTotalCount: false
        )

        let request = try #require(CapturingURLProtocol.lastRequest)
        let url = try #require(request.url)
        let query = url.query ?? ""

        #expect(url.path.contains("/rest/v1/lots"))
        #expect(query.contains("store_id=eq.11111111-1111-1111-1111-111111111111"))
        #expect(query.contains("order=created_at.desc"))
        // Slim projection — assert the distinguishing columns are in select.
        #expect(query.contains("select="))
        #expect(query.contains("vendor_name"))
        #expect(query.contains("offered_total_cents"))
        // Heavy column must NOT be requested on the slim path.
        #expect(!query.contains("transaction_stamp"))

        // Pagination: SDK translates range(from:to:) into offset + limit
        // query params. For Page(limit: 25, offset: 50) that's
        // offset=50&limit=25.
        #expect(query.contains("offset=50"))
        #expect(query.contains("limit=25"))
    }

    @Test("LotRepository.listItems applies status filter when provided")
    func lotListItemsWithStatus() async throws {
        CapturingURLProtocol.reset()
        let client = makeClient()
        let repo = SupabaseLotRepository(client: client)
        let storeId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        _ = try await repo.listItems(
            storeId: storeId,
            status: .open,
            page: Page(limit: 10, offset: 0),
            includeTotalCount: false
        )

        let request = try #require(CapturingURLProtocol.lastRequest)
        let query = request.url?.query ?? ""
        #expect(query.contains("store_id=eq.22222222-2222-2222-2222-222222222222"))
        #expect(query.contains("status=eq.open"))
    }

    @Test("LotRepository.listItems(includeTotalCount:) requests exact count")
    func lotListItemsWithCount() async throws {
        CapturingURLProtocol.reset()
        CapturingURLProtocol.cannedHeaders["Content-Range"] = "0-0/42"
        let client = makeClient()
        let repo = SupabaseLotRepository(client: client)
        let storeId = UUID()

        let paged = try await repo.listItems(
            storeId: storeId,
            status: nil,
            page: .default,
            includeTotalCount: true
        )

        let request = try #require(CapturingURLProtocol.lastRequest)
        // `count=exact` goes into the Prefer header.
        let prefer = request.value(forHTTPHeaderField: "Prefer") ?? ""
        #expect(prefer.contains("count=exact"), "Prefer was \(prefer)")
        #expect(paged.totalCount == 42)
    }

    @Test("ScanRepository.listItems filters by lot_id, orders ascending")
    func scanListItemsByLot() async throws {
        CapturingURLProtocol.reset()
        let client = makeClient()
        let repo = SupabaseScanRepository(client: client)
        let lotId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        _ = try await repo.listItems(lotId: lotId, page: .default, includeTotalCount: false)

        let request = try #require(CapturingURLProtocol.lastRequest)
        let query = request.url?.query ?? ""
        #expect(query.contains("lot_id=eq.33333333-3333-3333-3333-333333333333"))
        #expect(query.contains("order=created_at.asc"))
        // Heavy fields must not be fetched.
        #expect(!query.contains("ocr_raw_text"))
        #expect(!query.contains("captured_photo_url"))
    }

    @Test("ScanRepository.countPending issues a HEAD with exact count")
    func scanCountPending() async throws {
        CapturingURLProtocol.reset()
        CapturingURLProtocol.cannedHeaders["Content-Range"] = "*/7"
        let client = makeClient()
        let repo = SupabaseScanRepository(client: client)
        let storeId = UUID()

        let count = try await repo.countPending(storeId: storeId)

        let request = try #require(CapturingURLProtocol.lastRequest)
        #expect(request.httpMethod == "HEAD", "expected HEAD, got \(request.httpMethod ?? "nil")")
        let prefer = request.value(forHTTPHeaderField: "Prefer") ?? ""
        #expect(prefer.contains("count=exact"))
        let query = request.url?.query ?? ""
        #expect(query.contains("status=eq.pending_validation"))
        #expect(count == 7)
    }

    @Test("StoreMemberRepository.membership filters by both composite-key columns")
    func membershipCompositeKey() async throws {
        CapturingURLProtocol.reset()
        let client = makeClient()
        let repo = SupabaseStoreMemberRepository(client: client)
        let storeId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let userId = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

        _ = try await repo.membership(storeId: storeId, userId: userId)

        let request = try #require(CapturingURLProtocol.lastRequest)
        let query = request.url?.query ?? ""
        #expect(query.contains("store_id=eq.44444444-4444-4444-4444-444444444444"))
        #expect(query.contains("user_id=eq.55555555-5555-5555-5555-555555555555"))
    }

    @Test("Inserts use returning=minimal (no body echoed back)")
    func insertMinimalReturn() async throws {
        CapturingURLProtocol.reset()
        let client = makeClient()
        let repo = SupabaseLotRepository(client: client)
        let lot = LotDTO(
            id: UUID(),
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "X",
            notes: nil,
            status: "open",
            vendorName: nil,
            vendorContact: nil,
            offeredTotalCents: nil,
            marginRuleId: nil,
            transactionStamp: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await repo.insert(lot)

        let request = try #require(CapturingURLProtocol.lastRequest)
        let prefer = request.value(forHTTPHeaderField: "Prefer") ?? ""
        #expect(prefer.contains("return=minimal"), "Prefer was \(prefer)")
        #expect(request.httpMethod == "POST")
    }
}
