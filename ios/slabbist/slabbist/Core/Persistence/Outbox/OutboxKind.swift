import Foundation

enum OutboxKind: String, Codable, CaseIterable {
    case insertScan
    case updateScan
    case deleteScan
    case insertLot
    case updateLot
    case deleteLot
    case certLookupJob
    case priceCompJob

    /// Higher priority = dispatched first. See design spec: validation
    /// unblocks comp; writes happen in natural order behind them.
    /// Deletes are highest so a user-initiated remove takes precedence over
    /// background inserts/updates that might race against it.
    var priority: Int {
        switch self {
        case .deleteScan:     return 50
        case .deleteLot:      return 50
        case .certLookupJob:  return 40
        case .priceCompJob:   return 30
        case .insertScan:     return 20
        case .insertLot:      return 15
        case .updateScan:     return 10
        case .updateLot:      return 5
        }
    }
}

enum OutboxStatus: String, Codable, CaseIterable {
    case pending, inFlight, completed, failed
}
