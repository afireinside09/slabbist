import Foundation

nonisolated enum OutboxKind: String, Codable, CaseIterable {
    case insertScan
    case updateScan
    case updateScanOffer
    case updateScanBuyPrice
    case deleteScan
    case insertLot
    case updateLot
    case updateLotOffer
    case recomputeLotOffer
    case deleteLot
    case upsertVendor
    case archiveVendor
    case certLookupJob
    case priceCompJob

    /// Higher priority = dispatched first. See design spec: validation
    /// unblocks comp; writes happen in natural order behind them.
    /// Deletes are highest so a user-initiated remove takes precedence over
    /// background inserts/updates that might race against it.
    nonisolated var priority: Int {
        switch self {
        case .deleteScan:         return 50
        case .deleteLot:          return 50
        case .certLookupJob:      return 40
        case .priceCompJob:       return 30
        case .insertScan:         return 20
        case .insertLot:          return 15
        case .updateScan:         return 10
        case .updateScanOffer:    return 10
        case .updateScanBuyPrice: return 10
        case .upsertVendor:       return 8
        case .archiveVendor:      return 8
        case .updateLotOffer:     return 7
        case .recomputeLotOffer:  return 6
        case .updateLot:          return 5
        }
    }
}

nonisolated enum OutboxItemStatus: String, Codable, CaseIterable {
    case pending, inFlight, completed, failed
}
