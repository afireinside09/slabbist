import Foundation
import SwiftData
import Testing
@testable import slabbist

/// State-machine coverage for `OfferReviewView`'s commit flow. These tests
/// pin the bug fix from C4: before the rewrite, a synchronous throw from
/// `OfferUseCase.commit` left `isCommitting = true` while `commitError`
/// was set, so the CTA stayed locked on "Committing…" forever. With the
/// `CommitState` enum, `.error` and `.committing` are mutually exclusive —
/// these tests prove that contract is enforced.
@MainActor
struct OfferReviewViewStateTests {

    // MARK: - runCommit: synchronous throw lands in .error

    @Test("runCommit returns .error when the lot is in a non-acceptable state — the original bug stranded the CTA in .committing")
    func runCommitOnIneligibleLotReturnsError() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let kicker = OutboxKicker { /* no-op */ }
        // `.drafting` cannot transition to `.accepted` (the recordAcceptance
        // path) — so OfferUseCase will throw `InvalidTransition`. That's
        // our synchronous-throw scenario.
        let lot = Lot(
            id: UUID(),
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "L",
            createdAt: Date(),
            updatedAt: Date()
        )
        lot.lotOfferState = LotOfferState.drafting.rawValue
        context.insert(lot)
        try context.save()
        let repo = OfferUseCase(
            context: context,
            kicker: kicker,
            currentStoreId: lot.storeId,
            currentUserId: UUID()
        )

        // Belt-and-braces: also exercise the underlying repo directly to pin
        // which throw type lands here. If `OfferUseCase` changes its
        // acceptance rules and `.drafting -> .accepted` becomes legal, this
        // upstream guard will fail loudly before the view-state assertion
        // misleads us with a passing `.error` that came from a different
        // path. The new contract — synchronous throw -> `.error` — depends
        // on `recordAcceptance` actually throwing here.
        #expect(throws: OfferUseCase.InvalidTransition.self) {
            try repo.recordAcceptance(lot)
        }

        let next = OfferReviewView.runCommit(
            lot: lot,
            repo: repo,
            paymentMethod: "cash",
            paymentReference: nil,
            now: Date()
        )

        switch next {
        case .error(let msg):
            // The throw TYPE is pinned above (`#expect(throws:
            // InvalidTransition.self)`). Here we pin the user-facing intent:
            // a synchronous throw must surface as the friendly
            // `LocalizedError` copy in the `.error` payload — not strand the
            // CTA in `.committing`, and not leak the opaque
            // "(slabbist…error N.)" Foundation fallback the old assertion
            // relied on (InvalidTransition now conforms to LocalizedError).
            #expect(msg == OfferUseCase.InvalidTransition.notAllowed(from: .priced, to: .accepted).localizedDescription)
            #expect(!msg.isEmpty)
        default:
            Issue.record("expected .error, got \(next)")
        }
    }

    @Test("runCommit returns .committing(startedAt:) when the repo write succeeds locally")
    func runCommitHappyPathYieldsCommittingWithStartedAt() throws {
        let container = AppModelContainer.inMemory()
        let context = ModelContext(container)
        let kicker = OutboxKicker { /* no-op */ }
        let lot = Lot(
            id: UUID(),
            storeId: UUID(),
            createdByUserId: UUID(),
            name: "L",
            createdAt: Date(),
            updatedAt: Date()
        )
        // `.accepted` lets `runCommit` skip `recordAcceptance` and go straight
        // to `commit`, which enqueues the outbox item without throwing.
        lot.lotOfferState = LotOfferState.accepted.rawValue
        context.insert(lot)
        try context.save()
        let repo = OfferUseCase(
            context: context,
            kicker: kicker,
            currentStoreId: lot.storeId,
            currentUserId: UUID()
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let next = OfferReviewView.runCommit(
            lot: lot,
            repo: repo,
            paymentMethod: "cash",
            paymentReference: nil,
            now: now
        )

        switch next {
        case .committing(let startedAt):
            // The timestamp lets the timeout task compute its 10s deadline
            // from a stable point — pinning the contract here prevents a
            // future refactor from silently dropping it.
            #expect(startedAt == now)
        default:
            Issue.record("expected .committing, got \(next)")
        }
    }

    // MARK: - runCommitTimeoutIfNeeded

    @Test("runCommitTimeoutIfNeeded promotes .committing to .timedOut after the sleep and fires the announcement")
    func timeoutPromotesCommittingToTimedOut() async {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        var state: OfferReviewView.CommitState = .committing(startedAt: started)
        var announced = false

        await OfferReviewView.runCommitTimeoutIfNeeded(
            state: { state },
            set: { state = $0 },
            // Tests skip the 10s sleep — the production sleeper is the
            // only thing that needs the real Task.sleep.
            sleeper: { },
            announce: { announced = true }
        )

        switch state {
        case .timedOut(let startedAt):
            #expect(startedAt == started)
        default:
            Issue.record("expected .timedOut, got \(state)")
        }
        #expect(announced, "VoiceOver users need an announcement on the .committing → .timedOut transition")
    }

    @Test("runCommitTimeoutIfNeeded leaves state alone when .paid lands mid-sleep — no race")
    func timeoutDoesNothingWhenStateAdvancedMidSleep() async {
        // Simulate the production race: state is .committing at the start of
        // the sleep, but the hydrator flips the lot to .paid mid-sleep and
        // the onChange handler resets commitState to .idle before the sleep
        // returns. The helper must NOT clobber that with .timedOut.
        var state: OfferReviewView.CommitState = .committing(startedAt: Date())
        var announced = false
        await OfferReviewView.runCommitTimeoutIfNeeded(
            state: { state },
            set: { state = $0 },
            sleeper: {
                // Mid-sleep, the .paid drainer resolution arrives.
                state = .idle
            },
            announce: { announced = true }
        )

        switch state {
        case .idle:
            break
        default:
            Issue.record("expected .idle preserved, got \(state)")
        }
        #expect(!announced, "Announcement must not fire when the user has already been resolved to .paid")
    }

    @Test("runCommitTimeoutIfNeeded swallows CancellationError from the sleeper and does NOT promote .timedOut — cancellation is the design")
    func timeoutHonorsCancellationFromSleeper() async {
        // Production path: SwiftUI cancels `.task(id:)` when commitState
        // changes (e.g. `.paid` lands). The cancelled `Task.sleep` throws
        // CancellationError. The helper must swallow that at its boundary
        // AND must not promote .timedOut — otherwise a late timeout would
        // race the .paid resolution.
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        var state: OfferReviewView.CommitState = .committing(startedAt: started)
        var announced = false

        await OfferReviewView.runCommitTimeoutIfNeeded(
            state: { state },
            set: { state = $0 },
            sleeper: { throw CancellationError() },
            announce: { announced = true }
        )

        // State preserved as `.committing`; the parent `.task(id:)` is what
        // unmounts; we just don't do harm on the way out.
        switch state {
        case .committing:
            break
        default:
            Issue.record("expected .committing preserved on cancellation, got \(state)")
        }
        #expect(!announced, "Cancellation must not trigger the VoiceOver announcement")
    }

    @Test("runCommitTimeoutIfNeeded is a no-op when state is .idle (no timeout outside .committing)")
    func timeoutIsNoOpWhenNotCommitting() async {
        var state: OfferReviewView.CommitState = .idle
        var sleeperRan = false
        await OfferReviewView.runCommitTimeoutIfNeeded(
            state: { state },
            set: { state = $0 },
            sleeper: { sleeperRan = true },
            announce: { }
        )

        #expect(state == .idle)
        #expect(!sleeperRan, "No reason to spin the timeout sleeper while .idle")
    }

    // MARK: - CommitState contract

    // MARK: - Secondary actions are locked during in-flight commit (P0.2)

    @Test("Bounce back / Decline are disabled during .committing and .timedOut — tapping them mid-commit races the drainer against itself")
    func secondaryActionsLockedDuringCommit() {
        // The pre-fix bug let the user tap Decline while a commit was still
        // landing on the server. The drainer would then race a contradictory
        // state transition. This test pins the rule: secondaries only fire
        // when commit is at rest.
        #expect(OfferReviewView.secondaryActionsEnabled(for: .idle))
        #expect(OfferReviewView.secondaryActionsEnabled(for: .error("anything")))
        #expect(!OfferReviewView.secondaryActionsEnabled(for: .committing(startedAt: Date())))
        #expect(!OfferReviewView.secondaryActionsEnabled(for: .timedOut(startedAt: Date())))
    }

    @Test("CommitState .committing and .error are mutually exclusive — the C4 bug becomes unrepresentable")
    func commitStateMutualExclusivity() {
        // The original code held `isCommitting: Bool` AND `commitError: String?`.
        // The bug was the catch path setting `commitError` without resetting
        // `isCommitting`. The enum makes that illegal at the type level.
        let states: [OfferReviewView.CommitState] = [
            .idle,
            .committing(startedAt: Date()),
            .timedOut(startedAt: Date()),
            .error("boom"),
        ]
        // Sanity: Equatable is a load-bearing requirement for `.task(id: commitState)`.
        for s in states { #expect(s == s) }
        #expect(states[0] != states[1])
        #expect(states[1] != states[2])
        #expect(states[2] != states[3])
    }
}
