import Foundation
import Testing
import SwiftData
@testable import slabbist

/// Probe tests pinning which SwiftData `#Predicate` shapes work against
/// the `OutboxItem.status` enum on iOS 26.4. The Critic asked for evidence
/// that the workaround in `fetchBatch` is justified rather than cargo-
/// culted; these tests are the evidence.
///
/// Findings (iOS 26.4 simulator, Xcode 26.4):
/// * `$0.status == OutboxItemStatus.pending` — fails to COMPILE
///   ("key path cannot refer to enum case 'pending'").
/// * `$0.status.rawValue == "pending"` (literal String) — compiles but
///   TRAPS at runtime inside SQLite with `_assertionFailure` and
///   "type metadata for OutboxItemStatus" on the stack.
/// * `$0.status.rawValue == capturedString` — same trap.
/// * `$0.nextAttemptAt <= cutoff` (no enum touch) — works.
///
/// The trap is destructive (brk #1, process kill — no `try` recovery), so
/// the two "TRAP" tests below are `disabled(...)` by default. Flip the
/// flag to false to verify the trap is still reproducible on a new OS
/// build. If they ever start passing, we can re-enable predicate-pushed
/// filtering in `fetchBatch` / `statusSnapshot()`.
@Suite("OutboxItem #Predicate probe")
struct OutboxPredicateProbeTests {

    /// Set to `false` to actually exercise the trap-reproducing tests on
    /// a new OS version. Keep `true` in normal CI so the suite stays green.
    static let skipTrapReproductions: Bool = true

    @Test(
        "status.rawValue == \"pending\" in #Predicate TRAPS on iOS 26.4",
        .disabled(if: OutboxPredicateProbeTests.skipTrapReproductions,
                  "destructive trap — flip skipTrapReproductions to re-verify")
    )
    func rawValueStringLiteralPredicate() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        // Seed three rows in different statuses.
        let pendingItem = OutboxItem(
            id: UUID(), kind: .insertScan, payload: Data(),
            status: .pending, attempts: 0,
            createdAt: Date(), nextAttemptAt: Date()
        )
        let inflightItem = OutboxItem(
            id: UUID(), kind: .insertScan, payload: Data(),
            status: .inFlight, attempts: 0,
            createdAt: Date(), nextAttemptAt: Date()
        )
        let failedItem = OutboxItem(
            id: UUID(), kind: .insertScan, payload: Data(),
            status: .failed, attempts: 0,
            createdAt: Date(), nextAttemptAt: Date()
        )
        context.insert(pendingItem)
        context.insert(inflightItem)
        context.insert(failedItem)
        try context.save()

        // String-literal predicate — the formulation we now rely on.
        let pendingDescriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate<OutboxItem> { $0.status.rawValue == "pending" }
        )
        let failedDescriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate<OutboxItem> { $0.status.rawValue == "failed" }
        )

        // fetchCount must not hydrate rows AND must return the correct count.
        let pendingCount = try context.fetchCount(pendingDescriptor)
        let failedCount = try context.fetchCount(failedDescriptor)
        #expect(pendingCount == 1)
        #expect(failedCount == 1)
    }

    @Test(
        "compound predicate with nextAttemptAt + status.rawValue TRAPS",
        .disabled(if: OutboxPredicateProbeTests.skipTrapReproductions,
                  "destructive trap — flip skipTrapReproductions to re-verify")
    )
    func compoundPredicate() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let now = Date()
        // Eligible: pending, in the past.
        let eligible = OutboxItem(
            id: UUID(), kind: .insertScan, payload: Data(),
            status: .pending, attempts: 0,
            createdAt: now, nextAttemptAt: now.addingTimeInterval(-1)
        )
        // Future-scheduled pending row — should NOT match.
        let future = OutboxItem(
            id: UUID(), kind: .insertScan, payload: Data(),
            status: .pending, attempts: 0,
            createdAt: now, nextAttemptAt: now.addingTimeInterval(60)
        )
        // Failed row at the same time — should NOT match.
        let failed = OutboxItem(
            id: UUID(), kind: .insertScan, payload: Data(),
            status: .failed, attempts: 0,
            createdAt: now, nextAttemptAt: now.addingTimeInterval(-1)
        )
        context.insert(eligible)
        context.insert(future)
        context.insert(failed)
        try context.save()

        let cutoff = now
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate<OutboxItem> { item in
                item.status.rawValue == "pending" && item.nextAttemptAt <= cutoff
            }
        )
        let rows = try context.fetch(descriptor)
        #expect(rows.count == 1)
        #expect(rows.first?.id == eligible.id)
    }

    // NOTE: enum-case literals inside #Predicate (`$0.status == OutboxItemStatus.pending`)
    // don't compile — "key path cannot refer to enum case 'pending'". So the
    // candidate shapes we can even try at this layer are:
    //   1. captured enum case via `let cap = OutboxItemStatus.pending; ... $0.status == cap`
    //   2. captured String compare `$0.status.rawValue == "pending"`
    //   3. captured `String` variable compare `let raw = "pending"; ... $0.status.rawValue == raw`
    // (1) was the form the original drainer documented as "brittle across SwiftData
    // versions". (2) and (3) both trap at runtime in iOS 26.4 (see rawValueStringLiteralPredicate
    // above). The only known-good shape is no enum touch at all.

    @Test("predicate WITHOUT any enum touch (just Date) is the only known-good shape")
    func dateOnlyPredicate() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let item = OutboxItem(
            id: UUID(), kind: .insertScan, payload: Data(),
            status: .pending, attempts: 0,
            createdAt: Date(), nextAttemptAt: Date().addingTimeInterval(-1)
        )
        context.insert(item)
        try context.save()

        let cutoff = Date()
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate<OutboxItem> { $0.nextAttemptAt <= cutoff }
        )
        // This is the shape `fetchBatch` ships with — predicate handles the
        // Date window, enum filtering happens in memory after the fetch.
        let rows = try context.fetch(descriptor)
        #expect(rows.count == 1)
    }
}
