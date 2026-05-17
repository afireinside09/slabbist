import Foundation
import Testing
import SwiftData
@testable import slabbist

@Suite("LotsViewModel")
@MainActor
struct LotsViewModelTests {
    // MARK: - Helpers

    /// No-op kicker for tests that don't exercise the kick path.
    private static func noopKicker() -> OutboxKicker {
        OutboxKicker { }
    }

    @Test("createLot kicks the outbox after saving")
    func createLotKicks() async throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let counter = KickCounter()
        let kicker = OutboxKicker { await counter.increment() }

        let vm = LotsViewModel(
            context: context,
            kicker: kicker,
            currentUserId: UUID(),
            currentStoreId: UUID()
        )

        _ = try vm.createLot(name: "Test Lot")

        await counter.waitFor(value: 1)
        await #expect(counter.value == 1)
    }

    @Test("createLot inserts a Lot and outbox insertLot item in one transaction")
    func createsLotAndOutboxItem() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let vm = LotsViewModel(context: context, kicker: Self.noopKicker(), currentUserId: userId, currentStoreId: storeId)

        let lot = try vm.createLot(name: "Test Lot")

        #expect(lot.name == "Test Lot")
        #expect(lot.storeId == storeId)
        #expect(lot.createdByUserId == userId)
        #expect(lot.status == .open)

        let lots = try context.fetch(FetchDescriptor<Lot>())
        #expect(lots.count == 1)

        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        #expect(outbox.count == 1)
        #expect(outbox[0].kind == .insertLot)
        #expect(outbox[0].status == .pending)

        let payload = try JSONDecoder().decode(OutboxPayloads.InsertLot.self, from: outbox[0].payload)
        #expect(payload.id == lot.id.uuidString)
        #expect(payload.name == "Test Lot")
        #expect(payload.notes == nil)
    }

    @Test("createLot preserves notes through the outbox payload")
    func preservesNotesInPayload() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let vm = LotsViewModel(context: context, kicker: Self.noopKicker(), currentUserId: UUID(), currentStoreId: UUID())
        try vm.createLot(name: "With Notes", notes: "Tagged from the stack at the back counter")

        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        let payload = try JSONDecoder().decode(OutboxPayloads.InsertLot.self, from: outbox[0].payload)
        #expect(payload.notes == "Tagged from the stack at the back counter")
    }

    @Test("deleteScan removes the scan and enqueues a deleteScan outbox item")
    func deletesScanAndEnqueuesOutbox() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let lot = Lot(id: UUID(), storeId: storeId, createdByUserId: userId,
                      name: "Lot", createdAt: Date(), updatedAt: Date())
        let scan = Scan(id: UUID(), storeId: storeId, lotId: lot.id, userId: userId,
                        grader: .PSA, certNumber: "12345678",
                        createdAt: Date(), updatedAt: Date())
        context.insert(lot)
        context.insert(scan)
        try context.save()

        let vm = LotsViewModel(context: context, kicker: Self.noopKicker(), currentUserId: userId, currentStoreId: storeId)
        try vm.deleteScan(scan)

        let scans = try context.fetch(FetchDescriptor<Scan>())
        #expect(scans.isEmpty)

        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        let deleteItems = outbox.filter { $0.kind == .deleteScan }
        #expect(deleteItems.count == 1)
        let payload = try JSONDecoder().decode(OutboxPayloads.DeleteScan.self, from: deleteItems[0].payload)
        #expect(payload.id == scan.id.uuidString)
    }

    @Test("deleteLot cascades to all child scans and emits a deleteScan + deleteLot per row")
    func deleteLotCascadesScans() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let targetLot = Lot(id: UUID(), storeId: storeId, createdByUserId: userId,
                            name: "Target", createdAt: Date(), updatedAt: Date())
        let bystanderLot = Lot(id: UUID(), storeId: storeId, createdByUserId: userId,
                               name: "Bystander", createdAt: Date(), updatedAt: Date())
        let s1 = Scan(id: UUID(), storeId: storeId, lotId: targetLot.id, userId: userId,
                      grader: .PSA, certNumber: "11111111",
                      createdAt: Date(), updatedAt: Date())
        let s2 = Scan(id: UUID(), storeId: storeId, lotId: targetLot.id, userId: userId,
                      grader: .BGS, certNumber: "2222222222",
                      createdAt: Date(), updatedAt: Date())
        let bystanderScan = Scan(id: UUID(), storeId: storeId, lotId: bystanderLot.id, userId: userId,
                                 grader: .PSA, certNumber: "99999999",
                                 createdAt: Date(), updatedAt: Date())
        context.insert(targetLot)
        context.insert(bystanderLot)
        context.insert(s1)
        context.insert(s2)
        context.insert(bystanderScan)
        try context.save()

        let vm = LotsViewModel(context: context, kicker: Self.noopKicker(), currentUserId: userId, currentStoreId: storeId)
        try vm.deleteLot(targetLot)

        let lots = try context.fetch(FetchDescriptor<Lot>())
        #expect(lots.map(\.name) == ["Bystander"])

        let scans = try context.fetch(FetchDescriptor<Scan>())
        #expect(scans.count == 1)
        #expect(scans[0].certNumber == "99999999")

        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        let scanDeletes = outbox.filter { $0.kind == .deleteScan }
        let lotDeletes = outbox.filter { $0.kind == .deleteLot }
        #expect(scanDeletes.count == 2)
        #expect(lotDeletes.count == 1)
        let lotPayload = try JSONDecoder().decode(OutboxPayloads.DeleteLot.self, from: lotDeletes[0].payload)
        #expect(lotPayload.id == targetLot.id.uuidString)
    }

    @Test("setOfferCents persists the manual price and enqueues an updateScanOffer outbox item")
    func setOfferCentsPersistsAndEnqueues() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let lot = Lot(id: UUID(), storeId: storeId, createdByUserId: userId,
                      name: "Lot", createdAt: Date(), updatedAt: Date())
        let scan = Scan(id: UUID(), storeId: storeId, lotId: lot.id, userId: userId,
                        grader: .PSA, certNumber: "12345678",
                        createdAt: Date(), updatedAt: Date())
        context.insert(lot)
        context.insert(scan)
        try context.save()

        let vm = LotsViewModel(context: context, kicker: Self.noopKicker(), currentUserId: userId, currentStoreId: storeId)
        try vm.setOfferCents(scan: scan, cents: 4_999)

        #expect(scan.vendorAskCents == 4_999)

        let outbox = try context.fetch(FetchDescriptor<OutboxItem>())
        let offerItems = outbox.filter { $0.kind == .updateScanOffer }
        #expect(offerItems.count == 1)
        let payload = try JSONDecoder().decode(OutboxPayloads.UpdateScanOffer.self, from: offerItems[0].payload)
        #expect(payload.id == scan.id.uuidString)
        #expect(payload.vendor_ask_cents == 4_999)

        // Clearing flips the value back to nil and emits a second item with
        // an explicit null vendor_ask_cents — the worker contract for "remove".
        try vm.setOfferCents(scan: scan, cents: nil)
        #expect(scan.vendorAskCents == nil)
        let allOfferItems = try context.fetch(FetchDescriptor<OutboxItem>())
            .filter { $0.kind == .updateScanOffer }
        #expect(allOfferItems.count == 2)
        let clearPayload = try JSONDecoder().decode(
            OutboxPayloads.UpdateScanOffer.self,
            from: allOfferItems.last!.payload
        )
        #expect(clearPayload.vendor_ask_cents == nil)
    }

    @Test("listOpenLots returns only open lots for the current store, newest first")
    func listsOpenLotsNewestFirst() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)

        let userId = UUID()
        let storeId = UUID()
        let otherStoreId = UUID()

        let older = Lot(id: UUID(), storeId: storeId, createdByUserId: userId, name: "older",
                        createdAt: Date(timeIntervalSinceNow: -1000), updatedAt: Date())
        let newer = Lot(id: UUID(), storeId: storeId, createdByUserId: userId, name: "newer",
                        createdAt: Date(), updatedAt: Date())
        let closed = Lot(id: UUID(), storeId: storeId, createdByUserId: userId, name: "closed",
                         status: .closed, createdAt: Date(), updatedAt: Date())
        let otherStore = Lot(id: UUID(), storeId: otherStoreId, createdByUserId: userId, name: "other",
                             createdAt: Date(), updatedAt: Date())

        [older, newer, closed, otherStore].forEach(context.insert)
        try context.save()

        let vm = LotsViewModel(context: context, kicker: Self.noopKicker(), currentUserId: userId, currentStoreId: storeId)
        let lots = try vm.listOpenLots()

        #expect(lots.map(\.name) == ["newer", "older"])
    }
}

// MARK: - P0.2 — requireResolve must throw on missing-store paths so
// downstream sheets (ManualPriceSheet etc.) can surface an inline error
// rather than silently swallow the user's tap.

@Suite("LotsViewModel.requireResolve")
@MainActor
struct LotsViewModelRequireResolveTests {
    @Test("throws .storeUnavailable when no signed-in user")
    func throwsWhenSignedOut() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        // Default SessionStore has `userId == nil` until bootstrap lands.
        let session = SessionStore()
        let kicker = OutboxKicker { }

        do {
            _ = try LotsViewModel.requireResolve(context: context, kicker: kicker, session: session)
            Issue.record("requireResolve should throw when no user is signed in")
        } catch let error as LotsViewModel.ResolveError {
            #expect(error == .storeUnavailable)
            #expect(error.errorDescription?.isEmpty == false,
                    "ResolveError must carry a user-visible message so ManualPriceSheet's error row has copy")
        } catch {
            Issue.record("Expected LotsViewModel.ResolveError, got \(error)")
        }
    }

    @Test("throws .storeUnavailable when the signed-in user has no local Store")
    func throwsWhenNoStore() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let session = SessionStore()
        session.applyUITestUser(userId: UUID())  // signed in, but no Store row
        let kicker = OutboxKicker { }

        do {
            _ = try LotsViewModel.requireResolve(context: context, kicker: kicker, session: session)
            Issue.record("requireResolve should throw when the user has no local Store")
        } catch let error as LotsViewModel.ResolveError {
            #expect(error == .storeUnavailable)
        } catch {
            Issue.record("Expected LotsViewModel.ResolveError, got \(error)")
        }
    }

    @Test("succeeds when the signed-in user has a local Store")
    func succeedsWhenStoreExists() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let userId = UUID()
        let store = Store(id: UUID(), name: "Test Store", ownerUserId: userId, createdAt: Date())
        context.insert(store)
        try context.save()
        let session = SessionStore()
        session.applyUITestUser(userId: userId)

        let vm = try LotsViewModel.requireResolve(context: context, kicker: OutboxKicker { }, session: session)
        #expect(vm.currentUserId == userId)
        #expect(vm.currentStoreId == store.id)
    }
}

// MARK: - Test helpers

private actor KickCounter {
    var value: Int = 0
    private var continuations: [(Int, CheckedContinuation<Void, Never>)] = []

    func increment() {
        value += 1
        let now = value
        continuations = continuations.compactMap { (target, c) in
            if now >= target { c.resume(); return nil }
            return (target, c)
        }
    }

    func waitFor(value target: Int) async {
        if value >= target { return }
        await withCheckedContinuation { continuation in
            continuations.append((target, continuation))
        }
    }
}
