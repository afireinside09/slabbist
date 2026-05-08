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

    @Test("uniqueViolation on non-insert is permanent")
    func uniqueViolationOnUpdateIsPermanent() {
        let err = SupabaseError.uniqueViolation(message: "dup", underlying: NSError(domain: "x", code: 0))
        #expect(OutboxErrorClassifier.classify(err, for: .updateScan) == .permanent)
    }

    @Test("unauthorized → auth")
    func unauthorizedIsAuth() {
        #expect(OutboxErrorClassifier.classify(.unauthorized, for: kindInsert) == .auth)
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

    @Test("notFound on delete → success (already gone)")
    func notFoundOnDeleteIsSuccess() {
        let err = SupabaseError.notFound(table: "scans", id: nil)
        #expect(OutboxErrorClassifier.classify(err, for: kindDelete) == .success)
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
