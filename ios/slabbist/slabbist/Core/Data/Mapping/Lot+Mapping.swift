import Foundation
import Supabase

extension LotDTO {
    init(_ model: Lot) throws {
        let stamp: AnyJSON?
        if let data = model.transactionStamp {
            do {
                stamp = try JSONDecoder().decode(AnyJSON.self, from: data)
            } catch {
                throw ModelMappingError.invalidJSON(field: "transactionStamp", underlying: error)
            }
        } else {
            stamp = nil
        }

        self.init(
            id: model.id,
            storeId: model.storeId,
            createdByUserId: model.createdByUserId,
            name: model.name,
            notes: model.notes,
            status: model.status.rawValue,
            vendorName: model.vendorName,
            vendorContact: model.vendorContact,
            offeredTotalCents: model.offeredTotalCents,
            marginRuleId: model.marginRuleId,
            transactionStamp: stamp,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }
}

extension Lot {
    convenience init(dto: LotDTO) throws {
        guard let status = LotStatus(rawValue: dto.status) else {
            throw ModelMappingError.unknownEnumCase(type: "LotStatus", value: dto.status)
        }

        self.init(
            id: dto.id,
            storeId: dto.storeId,
            createdByUserId: dto.createdByUserId,
            name: dto.name,
            notes: dto.notes,
            status: status,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )

        self.vendorName = dto.vendorName
        self.vendorContact = dto.vendorContact
        self.offeredTotalCents = dto.offeredTotalCents
        self.marginRuleId = dto.marginRuleId
        self.transactionStamp = try Lot.encodeStamp(dto.transactionStamp)
    }

    func apply(_ dto: LotDTO) throws {
        guard let status = LotStatus(rawValue: dto.status) else {
            throw ModelMappingError.unknownEnumCase(type: "LotStatus", value: dto.status)
        }
        self.storeId = dto.storeId
        self.createdByUserId = dto.createdByUserId
        self.name = dto.name
        self.notes = dto.notes
        self.status = status
        self.vendorName = dto.vendorName
        self.vendorContact = dto.vendorContact
        self.offeredTotalCents = dto.offeredTotalCents
        self.marginRuleId = dto.marginRuleId
        self.transactionStamp = try Lot.encodeStamp(dto.transactionStamp)
        self.createdAt = dto.createdAt
        self.updatedAt = dto.updatedAt
    }

    private static func encodeStamp(_ stamp: AnyJSON?) throws -> Data? {
        guard let stamp else { return nil }
        do {
            return try JSONEncoder().encode(stamp)
        } catch {
            throw ModelMappingError.invalidJSON(field: "transactionStamp", underlying: error)
        }
    }
}
