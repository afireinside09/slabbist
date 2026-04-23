import Foundation
import Testing
@testable import slabbist

@Suite("DTO ↔ @Model Mapping")
struct ModelMappingTests {
    @Test("Store round-trips DTO → model → DTO")
    func storeRoundTrip() {
        let dto = StoreDTO(
            id: UUID(),
            name: "Main",
            ownerUserId: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let model = Store(dto: dto)
        let rebuilt = StoreDTO(model)

        #expect(rebuilt == dto)
    }

    @Test("StoreMember round-trips with known role")
    func storeMemberRoundTrip() throws {
        let dto = StoreMemberDTO(
            storeId: UUID(),
            userId: UUID(),
            role: "manager",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let model = try StoreMember(dto: dto)
        #expect(model.role == .manager)

        let rebuilt = StoreMemberDTO(model)
        #expect(rebuilt.role == "manager")
        #expect(rebuilt.storeId == dto.storeId)
        #expect(rebuilt.userId == dto.userId)
    }

    @Test("StoreMember throws on unknown role")
    func storeMemberUnknownRole() {
        let dto = StoreMemberDTO(
            storeId: UUID(),
            userId: UUID(),
            role: "superadmin",
            createdAt: Date()
        )

        #expect(throws: ModelMappingError.self) {
            _ = try StoreMember(dto: dto)
        }
    }

    @Test("Lot round-trips including optional fields")
    func lotRoundTrip() throws {
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
            transactionStamp: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let model = try Lot(dto: dto)
        #expect(model.status == .open)
        #expect(model.vendorName == "Shop A")
        #expect(model.offeredTotalCents == 12_345)

        let rebuilt = try LotDTO(model)
        #expect(rebuilt.id == dto.id)
        #expect(rebuilt.status == dto.status)
        #expect(rebuilt.vendorName == dto.vendorName)
        #expect(rebuilt.offeredTotalCents == dto.offeredTotalCents)
    }

    @Test("Lot apply updates mutable fields")
    func lotApply() throws {
        let initial = LotDTO(
            id: UUID(),
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "Original",
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
        let model = try Lot(dto: initial)

        let updated = LotDTO(
            id: initial.id,
            storeId: initial.storeId,
            createdByUserId: initial.createdByUserId,
            name: "Renamed",
            notes: "now with notes",
            status: "closed",
            vendorName: "Shop B",
            vendorContact: nil,
            offeredTotalCents: 999,
            marginRuleId: nil,
            transactionStamp: nil,
            createdAt: initial.createdAt,
            updatedAt: Date()
        )

        try model.apply(updated)

        #expect(model.name == "Renamed")
        #expect(model.notes == "now with notes")
        #expect(model.status == .closed)
        #expect(model.vendorName == "Shop B")
        #expect(model.offeredTotalCents == 999)
    }

    @Test("Lot throws on unknown status")
    func lotUnknownStatus() {
        let dto = LotDTO(
            id: UUID(),
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "x",
            notes: nil,
            status: "archived",
            vendorName: nil,
            vendorContact: nil,
            offeredTotalCents: nil,
            marginRuleId: nil,
            transactionStamp: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        #expect(throws: ModelMappingError.self) {
            _ = try Lot(dto: dto)
        }
    }

    @Test("Scan round-trips with enums and optionals")
    func scanRoundTrip() throws {
        let dto = ScanDTO(
            id: UUID(),
            storeId: UUID(),
            lotId: UUID(),
            userId: UUID(),
            grader: "PSA",
            certNumber: "12345678",
            grade: "10",
            status: "validated",
            ocrRawText: "raw text",
            ocrConfidence: 0.93,
            capturedPhotoURL: "https://example.com/x.jpg",
            offerCents: 5000,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let model = try Scan(dto: dto)
        #expect(model.grader == .PSA)
        #expect(model.status == .validated)
        #expect(model.grade == "10")
        #expect(model.offerCents == 5000)

        let rebuilt = ScanDTO(model)
        #expect(rebuilt == dto)
    }

    @Test("Scan throws on unknown grader")
    func scanUnknownGrader() {
        let dto = ScanDTO(
            id: UUID(),
            storeId: UUID(),
            lotId: UUID(),
            userId: UUID(),
            grader: "ACME",
            certNumber: "1",
            grade: nil,
            status: "pending_validation",
            ocrRawText: nil,
            ocrConfidence: nil,
            capturedPhotoURL: nil,
            offerCents: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        #expect(throws: ModelMappingError.self) {
            _ = try Scan(dto: dto)
        }
    }
}
