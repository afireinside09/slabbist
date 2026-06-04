import Foundation
import Testing
import SwiftData
import Supabase
@testable import slabbist

@Suite("OutboxDrainer")
struct OutboxDrainerTests {
    @Test("happy path: insertScan is dispatched and item deleted")
    @MainActor
    func happyPathInsertScan() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueInsertScan(id: scanId)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.insertedIds == [scanId])
        let count = await h.outboxCount()
        #expect(count == 0)
        #expect(h.status.pendingCount == 0)
        #expect(h.status.isDraining == false)
    }

    @Test("dispatches insertLot")
    @MainActor
    func dispatchesInsertLot() async throws {
        let h = Harness()
        let lotId = UUID()
        try await h.enqueueInsertLot(id: lotId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeLots.insertedIds == [lotId])
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("dispatches deleteScan")
    @MainActor
    func dispatchesDeleteScan() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueDeleteScan(id: scanId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeScans.deletedIds == [scanId])
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("dispatches deleteLot")
    @MainActor
    func dispatchesDeleteLot() async throws {
        let h = Harness()
        let lotId = UUID()
        try await h.enqueueDeleteLot(id: lotId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeLots.deletedIds == [lotId])
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("dispatches updateScan with patch fields")
    @MainActor
    func dispatchesUpdateScan() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueUpdateScan(id: scanId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeScans.patchCalls.count == 1)
        #expect(h.fakeScans.patchCalls[0].id == scanId)
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("updateScanOffer with cents: writes .integer(value)")
    @MainActor
    func dispatchesUpdateScanOfferWithCents() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueUpdateScanOffer(id: scanId, cents: 12500)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.patchCalls.count == 1)
        #expect(h.fakeScans.patchCalls[0].id == scanId)
        #expect(h.fakeScans.patchCalls[0].fields["vendor_ask_cents"] == .integer(12500))
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("updateScanOffer with cents nil: writes .null (clear semantic)")
    @MainActor
    func dispatchesUpdateScanOfferClearing() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueUpdateScanOffer(id: scanId, cents: nil)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.patchCalls.count == 1)
        #expect(h.fakeScans.patchCalls[0].id == scanId)
        #expect(h.fakeScans.patchCalls[0].fields["vendor_ask_cents"] == .null)
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("dispatches upsertVendor with full DTO")
    @MainActor
    func dispatchesUpsertVendor() async throws {
        let h = Harness()
        let vendorId = UUID()
        let storeId = UUID()
        try await h.enqueueUpsertVendor(
            id: vendorId,
            storeId: storeId,
            displayName: "Acme Cards"
        )
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeVendors.upsertedVendors.count == 1)
        #expect(h.fakeVendors.upsertedVendors[0].id == vendorId)
        #expect(h.fakeVendors.upsertedVendors[0].storeId == storeId)
        #expect(h.fakeVendors.upsertedVendors[0].displayName == "Acme Cards")
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("dispatches archiveVendor with archived_at + matching updated_at")
    @MainActor
    func dispatchesArchiveVendor() async throws {
        let h = Harness()
        let vendorId = UUID()
        let archivedAt = h.clock.current()
        try await h.enqueueArchiveVendor(id: vendorId, archivedAt: archivedAt)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeVendors.patchCalls.count == 1)
        #expect(h.fakeVendors.patchCalls[0].id == vendorId)
        let stamp = ISO8601DateFormatter().string(from: archivedAt)
        #expect(h.fakeVendors.patchCalls[0].fields["archived_at"] == .string(stamp))
        #expect(h.fakeVendors.patchCalls[0].fields["updated_at"] == .string(stamp))
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("dispatches updateLotOffer with snake_case patch fields")
    @MainActor
    func dispatchesUpdateLotOffer() async throws {
        let h = Harness()
        let lotId = UUID()
        let vendorId = UUID()
        let stateStamp = h.clock.current()
        try await h.enqueueUpdateLotOffer(
            id: lotId,
            vendorId: vendorId,
            vendorNameSnapshot: "Acme Cards",
            marginPctSnapshot: 0.18,
            lotOfferState: "offered",
            lotOfferStateUpdatedAt: stateStamp
        )
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeLots.patchCalls.count == 1)
        #expect(h.fakeLots.patchCalls[0].id == lotId)
        let f = h.fakeLots.patchCalls[0].fields
        #expect(f["vendor_id"] == .string(vendorId.uuidString))
        #expect(f["vendor_name_snapshot"] == .string("Acme Cards"))
        #expect(f["margin_pct_snapshot"] == .double(0.18))
        #expect(f["lot_offer_state"] == .string("offered"))
        let stateIso = ISO8601DateFormatter().string(from: stateStamp)
        #expect(f["lot_offer_state_updated_at"] == .string(stateIso))
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("updateLotOffer sends null for locally-cleared vendor/margin so a detach reaches the server")
    @MainActor
    func updateLotOfferClearsFieldsWithNull() async throws {
        let h = Harness()
        let lotId = UUID()
        // Vendor and margin are nil locally (e.g. the operator detached the
        // vendor or reverted the lot to ladder pricing). The patch MUST carry
        // them as explicit null — the lot is the offline-first authority, so
        // omitting them would leave the server's stale vendor/margin in place
        // and the two sides would diverge silently and forever.
        try await h.enqueueUpdateLotOffer(
            id: lotId,
            lotOfferState: "completed"
        )
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeLots.patchCalls.count == 1)
        let f = h.fakeLots.patchCalls[0].fields
        #expect(f["lot_offer_state"] == .string("completed"))
        #expect(f["updated_at"] != nil)
        // Cleared fields are sent as null, not dropped from the patch.
        #expect(f["vendor_id"] == .null)
        #expect(f["vendor_name_snapshot"] == .null)
        #expect(f["margin_pct_snapshot"] == .null)
        // `lot_offer_state_updated_at` stays conditionally omitted — it's a
        // change-stamp, not lot state the server must mirror.
        #expect(f["lot_offer_state_updated_at"] == nil)
    }

    @Test("dispatches updateScanBuyPrice with cents + overridden flag")
    @MainActor
    func dispatchesUpdateScanBuyPrice() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueUpdateScanBuyPrice(id: scanId, cents: 7500, overridden: true)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.patchCalls.count == 1)
        #expect(h.fakeScans.patchCalls[0].id == scanId)
        let f = h.fakeScans.patchCalls[0].fields
        #expect(f["buy_price_cents"] == .integer(7500))
        #expect(f["buy_price_overridden"] == .bool(true))
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("updateScanBuyPrice with cents nil clears the override (writes .null)")
    @MainActor
    func dispatchesUpdateScanBuyPriceClearing() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueUpdateScanBuyPrice(id: scanId, cents: nil, overridden: false)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.patchCalls.count == 1)
        let f = h.fakeScans.patchCalls[0].fields
        #expect(f["buy_price_cents"] == .null)
        #expect(f["buy_price_overridden"] == .bool(false))
    }

    @Test("dispatches recomputeLotOffer by invoking the Edge Function")
    @MainActor
    func dispatchesRecomputeLotOffer() async throws {
        let h = Harness()
        let lotId = UUID()
        try await h.enqueueRecomputeLotOffer(lotId: lotId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeLots.recomputeCalls == [lotId])
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    @Test("recomputeLotOffer 409 (terminal state) drains as success")
    @MainActor
    func recomputeLotOfferTreats409AsSuccess() async throws {
        let h = Harness()
        let lotId = UUID()
        // FunctionsError.httpError(409, ...) — simulates the server's
        // terminal-state guard. The drainer should swallow it.
        h.fakeLots.nextRecomputeError = FunctionsError.httpError(code: 409, data: Data())
        try await h.enqueueRecomputeLotOffer(lotId: lotId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        // The error was thrown before the call recorded, so recomputeCalls is empty.
        #expect(h.fakeLots.recomputeCalls.isEmpty)
        // But the outbox item drained — no retry queued.
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    // MARK: - D2: hydrate recomputeLotOffer response onto local Lot

    /// D2: the dispatch case used to `_ =` the response and discard it.
    /// Server-derived `offered_total_cents` + `lot_offer_state` never
    /// landed on the local cache. This test seeds a Lot, drains a
    /// recomputeLotOffer with a canned response that flips both fields,
    /// and asserts the mainContext row mirrors the server numbers.
    ///
    /// FAILS pre-D2 because nothing applies the response back onto the Lot.
    @Test("D2: recomputeLotOffer response writes offered_total_cents + lot_offer_state onto local Lot")
    @MainActor
    func recomputeLotOfferAppliesResponseToLocalLot() async throws {
        let h = Harness()
        let lotId = UUID()

        // Seed a Lot row on mainContext (where @Query-subscribed views
        // live). Starts in `.drafting` with no offered total.
        let main = h.container.mainContext
        let lot = Lot(
            id: lotId,
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "D2 Test Lot",
            lotOfferState: .drafting,
            createdAt: Date(),
            updatedAt: Date()
        )
        main.insert(lot)
        try main.save()

        // Server canned response: 50,000 cents priced.
        h.fakeLots.recomputeResponse = LotOfferRecomputeResponse(
            lot_id: lotId.uuidString,
            offered_total_cents: 50_000,
            lot_offer_state: LotOfferState.priced.rawValue
        )

        try await h.enqueueRecomputeLotOffer(lotId: lotId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        // The hydrator ran against the same store — fetch from mainContext
        // and assert both fields landed.
        let fetched = try main.fetch(
            FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })
        ).first
        #expect(fetched?.offeredTotalCents == 50_000)
        #expect(fetched?.lotOfferState == LotOfferState.priced.rawValue)
        #expect(fetched?.lotOfferStateUpdatedAt != nil)

        // And the outbox row drained.
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    /// D2 edge case: the lot was deleted locally between enqueue and
    /// dispatch (user discarded the lot while offline). The server
    /// recompute still ran successfully; we just have nothing to mirror
    /// back. The dispatch must NOT crash and the outbox row must still
    /// drain.
    @Test("D2: recomputeLotOffer drains cleanly when local Lot is missing")
    @MainActor
    func recomputeLotOfferSkipsMissingLot() async throws {
        let h = Harness()
        let lotId = UUID()

        // Do NOT seed a Lot — simulate a mid-dispatch local delete.
        h.fakeLots.recomputeResponse = LotOfferRecomputeResponse(
            lot_id: lotId.uuidString,
            offered_total_cents: 12_300,
            lot_offer_state: LotOfferState.priced.rawValue
        )

        try await h.enqueueRecomputeLotOffer(lotId: lotId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        // The outbox item drained — the server side succeeded, the missing
        // local Lot is a soft skip.
        #expect(h.fakeLots.recomputeCalls == [lotId])
        let count = await h.outboxCount()
        #expect(count == 0)

        // And no Lot got conjured into existence.
        let main = h.container.mainContext
        let all = try main.fetch(FetchDescriptor<Lot>())
        #expect(all.isEmpty)
    }

    /// D2: when the server returns a state the iOS enum doesn't recognize
    /// (forward-compat scenario), we still persist `offered_total_cents`
    /// (a pure number) but leave `lotOfferState` untouched rather than
    /// writing garbage that `LotOfferState(rawValue:)` would fall back to
    /// `.drafting` on every read.
    @Test("D2: recomputeLotOffer persists offered_total_cents even when lot_offer_state is unknown")
    @MainActor
    func recomputeLotOfferUnknownStatePersistsTotal() async throws {
        let h = Harness()
        let lotId = UUID()

        let main = h.container.mainContext
        let lot = Lot(
            id: lotId,
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "Forward-compat Lot",
            lotOfferState: .priced,
            createdAt: Date(),
            updatedAt: Date()
        )
        main.insert(lot)
        try main.save()

        h.fakeLots.recomputeResponse = LotOfferRecomputeResponse(
            lot_id: lotId.uuidString,
            offered_total_cents: 99_000,
            lot_offer_state: "shipped_to_grader" // not in LotOfferState
        )

        try await h.enqueueRecomputeLotOffer(lotId: lotId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        let fetched = try main.fetch(
            FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })
        ).first
        #expect(fetched?.offeredTotalCents == 99_000)
        // State stays where we put it.
        #expect(fetched?.lotOfferState == LotOfferState.priced.rawValue)
    }

    /// P2.2: pin the hydrator's malformed-UUID guard. The drainer's
    /// dispatch case also throws on a bad `lot_id` upstream, but the
    /// hydrator's own throw is the safety net if the response shape ever
    /// changes server-side. Staging a bad `lot_id` in the canned response
    /// (after the drainer has already validated its own payload) exercises
    /// the hydrator-side branch directly: it must throw
    /// `OutboxBridgeError.malformedPayload`, the drainer's classifier must
    /// route the outbox row to `.failed` with the hydrator's reason in
    /// `lastError`, and no Lot must be inserted/mutated.
    @Test("D2 (P2.2): hydrator malformed lot_id routes outbox row to .failed")
    @MainActor
    func recomputeLotOfferMalformedResponseLotIdMarksFailed() async throws {
        let h = Harness()
        let lotId = UUID()

        // The outbox payload is well-formed (drainer's own UUID guard
        // passes), but the canned response carries garbage so the
        // hydrator's guard fires.
        h.fakeLots.recomputeResponse = LotOfferRecomputeResponse(
            lot_id: "not-a-uuid",
            offered_total_cents: 12_345,
            lot_offer_state: LotOfferState.priced.rawValue
        )

        try await h.enqueueRecomputeLotOffer(lotId: lotId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        // The repo was called (proof we reached dispatch).
        #expect(h.fakeLots.recomputeCalls == [lotId])

        // The outbox row is now `.failed` carrying the hydrator's message.
        let snap = try await h.firstOutboxItem()
        #expect(snap.status == .failed)
        #expect(snap.lastError?.contains("LotOfferRecomputeHydrator") == true)
        #expect(snap.lastError?.contains("lot_id") == true)

        // No Lot was conjured.
        let main = h.container.mainContext
        let all = try main.fetch(FetchDescriptor<Lot>())
        #expect(all.isEmpty)
    }

    /// P2.3 (option a): the drainer's 409 catch is the production safety
    /// net against terminal-state regression — when the lot is `.paid`
    /// locally and the server returns 409 from `/lot-offer-recompute`,
    /// the hydrator must NOT run and the local terminal state must be
    /// preserved. Locks the inferred safety net into a real assertion so
    /// a future refactor of the 409 catch can't silently break it.
    @Test("D2 (P2.3): terminal-state 409 preserves local Lot state and drains outbox")
    @MainActor
    func recomputeLotOffer409PreservesTerminalState() async throws {
        let h = Harness()
        let lotId = UUID()

        // Seed a Lot in `.paid` (terminal) — the case where the server's
        // 409 guard fires because the iOS local state is authoritative.
        let main = h.container.mainContext
        let lot = Lot(
            id: lotId,
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "Paid Lot",
            lotOfferState: .paid,
            createdAt: Date(),
            updatedAt: Date()
        )
        lot.offeredTotalCents = 77_500
        main.insert(lot)
        try main.save()

        // Server returns 409 — the recompute repo throws BEFORE the
        // hydrator is called. The drainer's catch swallows the 409.
        h.fakeLots.nextRecomputeError = FunctionsError.httpError(code: 409, data: Data())

        try await h.enqueueRecomputeLotOffer(lotId: lotId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        // Outbox drained as success (terminal-state guard is convergent).
        let count = await h.outboxCount()
        #expect(count == 0)

        // Local terminal state preserved — the hydrator never ran.
        let fetched = try main.fetch(
            FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })
        ).first
        #expect(fetched?.lotOfferState == LotOfferState.paid.rawValue)
        #expect(fetched?.offeredTotalCents == 77_500)
    }

    /// P2.4: when the recompute response matches the local cache byte-for-
    /// byte (common after offline→online when the kicker fires and the
    /// server returns the same numbers we already have), the hydrator must
    /// short-circuit before bumping `lot.updatedAt`. Otherwise every kick
    /// fans out spurious `@Query` invalidations to any view sorting by
    /// `updatedAt`.
    @Test("D2 (P2.4): no-op recompute response leaves lot.updatedAt unchanged")
    @MainActor
    func recomputeLotOfferNoOpDoesNotBumpUpdatedAt() async throws {
        let h = Harness()
        let lotId = UUID()
        let originalUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let main = h.container.mainContext
        let lot = Lot(
            id: lotId,
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "Steady Lot",
            lotOfferState: .priced,
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: originalUpdatedAt
        )
        lot.offeredTotalCents = 42_000
        main.insert(lot)
        try main.save()

        // Server returns identical numbers — no diff to apply.
        h.fakeLots.recomputeResponse = LotOfferRecomputeResponse(
            lot_id: lotId.uuidString,
            offered_total_cents: 42_000,
            lot_offer_state: LotOfferState.priced.rawValue
        )

        try await h.enqueueRecomputeLotOffer(lotId: lotId)
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        let fetched = try main.fetch(
            FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })
        ).first
        // Numbers unchanged.
        #expect(fetched?.offeredTotalCents == 42_000)
        #expect(fetched?.lotOfferState == LotOfferState.priced.rawValue)
        // updatedAt NOT bumped — proves the hydrator short-circuited.
        #expect(fetched?.updatedAt == originalUpdatedAt)
    }

    @Test("dispatches commitTransaction and hydrates locally")
    @MainActor
    func dispatchesCommitTransaction() async throws {
        let h = Harness()
        let lotId = UUID()
        let payload = OutboxPayloads.CommitTransaction(
            lot_id: lotId.uuidString,
            payment_method: "cash",
            payment_reference: nil,
            vendor_id: nil,
            vendor_name_override: nil
        )
        let encoded = try JSONEncoder().encode(payload)
        try await h.drainer._testEnqueue(
            id: UUID(), kind: .commitTransaction,
            payload: encoded,
            createdAt: h.clock.current(), nextAttemptAt: h.clock.current()
        )
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeTransactions.commitCalls.count == 1)
        #expect(h.fakeTransactions.commitCalls[0].lot_id == lotId.uuidString)
    }

    @Test("dispatches voidTransaction")
    @MainActor
    func dispatchesVoidTransaction() async throws {
        let h = Harness()
        let txnId = UUID()
        let payload = OutboxPayloads.VoidTransaction(
            transaction_id: txnId.uuidString,
            reason: "ui test"
        )
        let encoded = try JSONEncoder().encode(payload)
        try await h.drainer._testEnqueue(
            id: UUID(), kind: .voidTransaction,
            payload: encoded,
            createdAt: h.clock.current(), nextAttemptAt: h.clock.current()
        )
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeTransactions.voidCalls.count == 1)
        #expect(h.fakeTransactions.voidCalls[0].transactionId == txnId)
        #expect(h.fakeTransactions.voidCalls[0].reason == "ui test")
    }

    // MARK: - 7.3 error-classifier tests

    @Test("409 (uniqueViolation) on insertScan deletes the item — idempotent success")
    @MainActor
    func conflictOnInsertIsSuccess() async throws {
        let h = Harness()
        let scanId = UUID()
        h.fakeScans.nextError = SupabaseError.uniqueViolation(
            message: "dup",
            underlying: NSError(domain: "x", code: 0)
        )
        try await h.enqueueInsertScan(id: scanId)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        let count = await h.outboxCount()
        #expect(count == 0)
        #expect(h.fakeScans.insertedIds.isEmpty)
    }

    @Test("transient error then success: backoff schedules retry, second kick after clock advance lands")
    @MainActor
    func transientThenSuccess() async throws {
        let h = Harness()
        let scanId = UUID()
        h.fakeScans.nextError = SupabaseError.transport(underlying: URLError(.timedOut))
        try await h.enqueueInsertScan(id: scanId)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.insertedIds.isEmpty)
        let count1 = await h.outboxCount()
        #expect(count1 == 1)

        let item1 = try await h.firstOutboxItem()
        #expect(item1.attempts == 1)
        #expect(item1.status == .pending)
        #expect(item1.nextAttemptAt > h.clock.current())

        h.clock.advance(10) // jump past the backoff window
        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.fakeScans.insertedIds == [scanId])
        let count2 = await h.outboxCount()
        #expect(count2 == 0)
    }

    @Test("401 pauses the queue; subsequent kicks no-op until unpause()")
    @MainActor
    func authErrorPausesQueue() async throws {
        let h = Harness()
        let scanId = UUID()
        h.fakeScans.nextError = SupabaseError.unauthorized
        try await h.enqueueInsertScan(id: scanId)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        #expect(h.status.isPaused == true)
        #expect(h.fakeScans.insertedIds.isEmpty)
        let count = await h.outboxCount()
        #expect(count == 1)

        // Subsequent kick while paused: no repo call (the nextError was
        // consumed on the first attempt, so a second drain-pass would
        // succeed if it ran — proving it didn't).
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeScans.insertedIds.isEmpty)

        // Unpause and kick again — should drain.
        await h.drainer.unpause()
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeScans.insertedIds == [scanId])
    }

    @Test("permanent (forbidden / RLS) marks item .failed and stops retrying")
    @MainActor
    func permanentMarksFailed() async throws {
        let h = Harness()
        let scanId = UUID()
        h.fakeScans.nextError = SupabaseError.forbidden(underlying: NSError(domain: "x", code: 0))
        try await h.enqueueInsertScan(id: scanId)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        let item = try await h.firstOutboxItem()
        #expect(item.status == .failed)
        #expect(item.lastError != nil)

        // Re-kick: failed items are not re-fetched.
        await h.drainer.kickAndWait()
        await h.waitForIdle()
        #expect(h.fakeScans.insertedIds.isEmpty)
    }

    // MARK: - 7.4 ordering + dedupe tests

    @Test("ordering: deleteScan precedes insertLot precedes updateLotOffer")
    @MainActor
    func priorityOrdering() async throws {
        let h = Harness()
        let scanId = UUID(); let lotIdA = UUID(); let lotIdB = UUID()
        let now = h.clock.current()
        // All three items share `nextAttemptAt == now` so the drainer's
        // `nextAttemptAt <= now` fetch predicate picks up the whole batch.
        // Priority is what's being tested — kind priority (50/15/7), not
        // chronological order — so a staggered `createdAt` would actually
        // filter rows out under TestClock (which doesn't advance) and the
        // drainer would never see the lower-priority items.
        try await h.enqueueUpdateLotOffer(id: lotIdB, lotOfferState: "presented", createdAt: now)
        try await h.enqueueInsertLot(id: lotIdA, createdAt: now)
        try await h.enqueueDeleteScan(id: scanId, createdAt: now)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        // After the drain, all three items should be gone.
        let count = await h.outboxCount()
        #expect(count == 0)

        // Recorders preserve call order — assert the chronological dispatch
        // sequence reflects priority, not enqueue order:
        //   deleteScan (50) → insertLot (15) → updateLotOffer (7)
        #expect(h.fakeScans.deletedIds == [scanId])
        #expect(h.fakeLots.insertedIds == [lotIdA])
        #expect(h.fakeLots.patchCalls.map(\.id) == [lotIdB])
    }

    @Test("concurrent kicks dedupe — only one drain pass executes")
    @MainActor
    func concurrentKicksDedupe() async throws {
        let h = Harness()
        let scanId = UUID()
        try await h.enqueueInsertScan(id: scanId)

        // Three concurrent kicks. Two should hit the `guard !isDraining`
        // early-return; only the first does any work.
        async let a: Void = h.drainer.kickAndWait()
        async let b: Void = h.drainer.kickAndWait()
        async let c: Void = h.drainer.kickAndWait()
        _ = await (a, b, c)
        await h.waitForIdle()

        // Repo records exactly one insert (not three).
        #expect(h.fakeScans.insertedIds.count == 1)
        let count = await h.outboxCount()
        #expect(count == 0)
    }

    // MARK: - 7.5 decode-failure resilience

    @Test("corrupt payload marks item .failed without crashing the loop")
    @MainActor
    func decodeFailureMarksFailed() async throws {
        let h = Harness()
        // Insert one valid + one corrupt; the valid one should still drain.
        let valid = UUID()
        try await h.enqueueInsertScan(id: valid)
        try await h.enqueueCorruptItem(kind: .insertScan)

        await h.drainer.kickAndWait()
        await h.waitForIdle()

        // The valid item drained successfully.
        #expect(h.fakeScans.insertedIds == [valid])

        // The corrupt one is still in the outbox, marked .failed.
        let count = await h.outboxCount()
        #expect(count == 1)
        let item = try await h.firstOutboxItem()
        #expect(item.status == .failed)
    }
}
