import Foundation
import Testing
@testable import slabbist

@Suite("OutboxErrorClassifier")
struct OutboxErrorClassifierTests {
    let kindInsert: OutboxKind = .insertScan
    let kindUpdate: OutboxKind = .updateScan
    let kindDelete: OutboxKind = .deleteScan

    @Test("URLError network errors are transient")
    func urlErrorTransient() {
        for code in [URLError.notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotFindHost] {
            let err = SupabaseError.transport(underlying: URLError(code))
            #expect(OutboxErrorClassifier.classify(err, for: kindInsert) == .transient)
        }
    }

    @Test("uniqueViolation is success on inserts")
    func uniqueViolationOnInsertIsSuccess() {
        let err = SupabaseError.uniqueViolation(message: "dup", underlying: NSError(domain: "x", code: 0))
        #expect(OutboxErrorClassifier.classify(err, for: .insertScan) == .success)
        #expect(OutboxErrorClassifier.classify(err, for: .insertLot) == .success)
    }

    @Test("uniqueViolation on every non-insert kind is permanent")
    func uniqueViolationOnNonInsertIsPermanent() {
        let err = SupabaseError.uniqueViolation(message: "dup", underlying: NSError(domain: "x", code: 0))
        let nonInsertKinds: [OutboxKind] = [
            .updateScan, .updateScanOffer, .deleteScan,
            .updateLot, .deleteLot,
            .certLookupJob, .priceCompJob
        ]
        for kind in nonInsertKinds {
            #expect(OutboxErrorClassifier.classify(err, for: kind) == .permanent,
                    "expected .permanent for \(kind)")
        }
    }

    @Test("unauthorized → auth(.reconnecting) — initial pause is recoverable")
    func unauthorizedIsAuth() {
        // The classifier can't tell mid-refresh from "user is gone" — it
        // defaults to `.reconnecting`. The drainer escalates to `.signedOut`
        // after repeated auth pauses (see OutboxDrainer.handle).
        #expect(OutboxErrorClassifier.classify(.unauthorized, for: kindInsert) == .auth(.reconnecting))
    }

    @Test("forbidden (RLS) → permanent")
    func forbiddenIsPermanent() {
        let err = SupabaseError.forbidden(underlying: NSError(domain: "x", code: 0))
        #expect(OutboxErrorClassifier.classify(err, for: kindInsert) == .permanent)
    }

    @Test("constraintViolation (FK / NOT NULL / CHECK) → permanent")
    func constraintViolationIsPermanent() {
        let err = SupabaseError.constraintViolation(message: "fk", underlying: NSError(domain: "x", code: 0))
        #expect(OutboxErrorClassifier.classify(err, for: kindInsert) == .permanent)
    }

    @Test("notFound on both delete kinds is success (already gone)")
    func notFoundOnDeleteIsSuccess() {
        let err = SupabaseError.notFound(table: "scans", id: nil)
        #expect(OutboxErrorClassifier.classify(err, for: .deleteScan) == .success)
        #expect(OutboxErrorClassifier.classify(err, for: .deleteLot) == .success)
    }

    @Test("notFound on update → permanent (we lost the row server-side)")
    func notFoundOnUpdateIsPermanent() {
        let err = SupabaseError.notFound(table: "scans", id: nil)
        #expect(OutboxErrorClassifier.classify(err, for: kindUpdate) == .permanent)
    }

    @Test("transport with non-URLError underlying is transient")
    func transportFallbackIsTransient() {
        let err = SupabaseError.transport(underlying: NSError(domain: "rand", code: 42))
        #expect(OutboxErrorClassifier.classify(err, for: kindInsert) == .transient)
    }
}
