import Foundation
import SwiftData
import Testing
@testable import slabbist

/// Round-trip tests for the offer repository: auto-buy-price derivation,
/// override stickiness, lot-margin recompute, and the `LotOfferState`
/// transition whitelist. Pairs with `OfferPricingServiceTests` (pure math)
/// so the SwiftData + state-machine side has its own coverage.
@MainActor
struct OfferRepositoryTests {
    private func makeContext() -> (OfferRepository, ModelContext, Lot, Scan) {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let storeId = UUID()
        let userId = UUID()
        let kicker = OutboxKicker { /* no-op for tests */ }
        let repo = OfferRepository(
            context: context,
            kicker: kicker,
            currentStoreId: storeId,
            currentUserId: userId
        )
        let lot = Lot(
            id: UUID(),
            storeId: storeId,
            createdByUserId: userId,
            name: "L",
            createdAt: Date(),
            updatedAt: Date()
        )
        lot.marginPctSnapshot = 0.6
        let scan = Scan(
            id: UUID(),
            storeId: storeId,
            lotId: lot.id,
            userId: userId,
            grader: .PSA,
            certNumber: "1",
            createdAt: Date(),
            updatedAt: Date()
        )
        scan.reconciledHeadlinePriceCents = 1000
        context.insert(lot)
        context.insert(scan)
        try? context.save()
        return (repo, context, lot, scan)
    }

    @Test func applyAutoBuyPriceFillsValueWhenCompLands() throws {
        let (repo, _, lot, scan) = makeContext()
        let result = try repo.applyAutoBuyPrice(scan: scan, lot: lot)
        #expect(result == 600)
        #expect(scan.buyPriceCents == 600)
        #expect(scan.buyPriceOverridden == false)
    }

    @Test func applyAutoBuyPriceSkipsOverriddenScans() throws {
        let (repo, _, lot, scan) = makeContext()
        scan.buyPriceCents = 999
        scan.buyPriceOverridden = true
        let result = try repo.applyAutoBuyPrice(scan: scan, lot: lot)
        #expect(result == 999)
        #expect(scan.buyPriceCents == 999)
    }

    @Test func setLotMarginRecomputesNonOverriddenScans() throws {
        let (repo, _, lot, scan) = makeContext()
        scan.buyPriceCents = 600
        try repo.setLotMargin(0.7, on: lot)
        #expect(scan.buyPriceCents == 700)
    }

    @Test func setLotMarginPreservesOverriddenScans() throws {
        let (repo, _, lot, scan) = makeContext()
        scan.buyPriceCents = 999
        scan.buyPriceOverridden = true
        try repo.setLotMargin(0.5, on: lot)
        #expect(scan.buyPriceCents == 999)
    }

    @Test func bounceBackReturnsPresentedToPriced() throws {
        let (repo, _, lot, _) = makeContext()
        lot.lotOfferState = LotOfferState.presented.rawValue
        try repo.bounceBack(lot)
        #expect(lot.lotOfferState == LotOfferState.priced.rawValue)
    }

    @Test func acceptedCanDropBackToPresented() throws {
        #expect(OfferRepository.canTransition(from: .accepted, to: .presented) == true)
        #expect(OfferRepository.canTransition(from: .accepted, to: .declined) == true)
        #expect(OfferRepository.canTransition(from: .accepted, to: .paid) == true)
    }

    @Test func sendToOfferRejectsDrafting() throws {
        let (repo, _, lot, _) = makeContext()
        // drafting can't transition directly to presented (requires priced first)
        #expect(throws: OfferRepository.InvalidTransition.self) {
            try repo.sendToOffer(lot)
        }
    }

    @Test func setBuyPriceFlipsDraftingToPriced() throws {
        let (repo, _, lot, scan) = makeContext()
        // makeContext() leaves the lot at its `.drafting` default.
        #expect(lot.lotOfferState == LotOfferState.drafting.rawValue)
        try repo.setBuyPrice(500, scan: scan, overridden: true)
        #expect(lot.lotOfferState == LotOfferState.priced.rawValue)
    }

    @Test func setBuyPriceFlipsPricedBackToDraftingWhenCleared() throws {
        let (repo, _, lot, scan) = makeContext()
        lot.lotOfferState = LotOfferState.priced.rawValue
        scan.buyPriceCents = 500
        try repo.setBuyPrice(nil, scan: scan, overridden: false)
        #expect(lot.lotOfferState == LotOfferState.drafting.rawValue)
    }

    @Test func applyAutoBuyPriceFlipsDraftingToPriced() throws {
        let (repo, _, lot, scan) = makeContext()
        #expect(lot.lotOfferState == LotOfferState.drafting.rawValue)
        _ = try repo.applyAutoBuyPrice(scan: scan, lot: lot)
        #expect(lot.lotOfferState == LotOfferState.priced.rawValue)
    }

    @Test func setBuyPriceRejectedOnTerminalLotState() throws {
        let (repo, _, lot, scan) = makeContext()
        lot.lotOfferState = LotOfferState.paid.rawValue
        #expect(throws: OfferRepository.InvalidTransition.self) {
            try repo.setBuyPrice(500, scan: scan, overridden: true)
        }
        // Scan value must not have shifted under the failed write.
        #expect(scan.buyPriceCents == nil)
    }
}
