import Foundation
import Testing
import Supabase
@testable import slabbist

@Suite("DTO Coding")
struct DTOCodingTests {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @Test("StoreDTO encodes column names as snake_case")
    func storeEncodesSnakeCase() throws {
        let dto = StoreDTO(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Main Street",
            ownerUserId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try encoder.encode(dto)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"owner_user_id\""))
        #expect(json.contains("\"created_at\""))
        #expect(!json.contains("\"ownerUserId\""))
    }

    @Test("StoreDTO round-trips through Codable")
    func storeRoundTrips() throws {
        let original = StoreDTO(
            id: UUID(),
            name: "Card Zone",
            ownerUserId: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(StoreDTO.self, from: data)

        #expect(decoded == original)
    }

    @Test("StoreMemberDTO exposes composite id for Identifiable")
    func storeMemberCompositeId() {
        let storeId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let userId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let dto = StoreMemberDTO(
            storeId: storeId,
            userId: userId,
            role: "owner",
            createdAt: Date()
        )

        #expect(dto.id == "\(storeId.uuidString):\(userId.uuidString)")
    }

    @Test("LotDTO uses snake_case for every field")
    func lotEncodesSnakeCase() throws {
        let dto = LotDTO(
            id: UUID(),
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "April drop",
            notes: "bulk intake",
            status: "open",
            vendorName: "Shop A",
            vendorContact: "a@b.c",
            offeredTotalCents: 12_345,
            marginRuleId: UUID(),
            transactionStamp: .string("pending"),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let data = try encoder.encode(dto)
        let json = String(data: data, encoding: .utf8)!

        for key in [
            "store_id", "created_by_user_id", "vendor_name", "vendor_contact",
            "offered_total_cents", "margin_rule_id", "transaction_stamp",
            "created_at", "updated_at"
        ] {
            #expect(json.contains("\"\(key)\""), "expected snake_case key \(key) in \(json)")
        }
    }

    @Test("ScanDTO uses snake_case for every field")
    func scanEncodesSnakeCase() throws {
        let dto = ScanDTO(
            id: UUID(),
            storeId: UUID(),
            lotId: UUID(),
            userId: UUID(),
            grader: "PSA",
            certNumber: "12345678",
            grade: "10",
            status: "validated",
            ocrRawText: "raw",
            ocrConfidence: 0.92,
            capturedPhotoURL: "https://example.com/p.jpg",
            vendorAskCents: 50_00,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let data = try encoder.encode(dto)
        let json = String(data: data, encoding: .utf8)!

        for key in [
            "store_id", "lot_id", "user_id", "cert_number", "ocr_raw_text",
            "ocr_confidence", "captured_photo_url", "vendor_ask_cents",
            "created_at", "updated_at"
        ] {
            #expect(json.contains("\"\(key)\""), "expected snake_case key \(key) in \(json)")
        }
    }
}
