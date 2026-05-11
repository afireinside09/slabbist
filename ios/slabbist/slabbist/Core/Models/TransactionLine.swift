import Foundation
import SwiftData

@Model
final class TransactionLine {
    /// Composite "{transactionId}:{scanId}" — SwiftData @Model needs a single unique attribute
    /// for the iOS-side cache. Server-side uniqueness lives in (transaction_id, scan_id) PK.
    @Attribute(.unique) var compositeKey: String
    var transactionId: UUID
    var scanId: UUID
    var lineIndex: Int
    var buyPriceCents: Int64
    var identitySnapshotJSON: Data

    init(
        transactionId: UUID, scanId: UUID, lineIndex: Int,
        buyPriceCents: Int64, identitySnapshotJSON: Data
    ) {
        self.compositeKey = "\(transactionId.uuidString):\(scanId.uuidString)"
        self.transactionId = transactionId
        self.scanId = scanId
        self.lineIndex = lineIndex
        self.buyPriceCents = buyPriceCents
        self.identitySnapshotJSON = identitySnapshotJSON
    }
}
