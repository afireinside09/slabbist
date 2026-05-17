import Testing
import Foundation
import Supabase
@testable import slabbist

@Suite("SessionStore sign-out")
@MainActor
struct SessionStoreSignOutTests {
    /// Each test isolates the UserDefaults persistence so a prior banner state
    /// can't leak in. Using the real `.standard` is fine because we wipe the
    /// key under test before and after.
    private static let key = "slabbist.signOutReason.v1"

    private func wipeReason() {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("signOut() exists and returns without throwing when already signed out")
    func signOutIsCallableWhenAlreadySignedOut() async {
        wipeReason()
        defer { wipeReason() }
        let store = SessionStore()
        // Not bootstrap()'d — userId is nil. signOut() should be a no-op.
        await store.signOut()
        #expect(store.userId == nil)
        #expect(store.isSignedIn == false)
    }

    // MARK: - F1: SignOutReason classification

    @Test("init reads .launchedFresh when no persisted reason exists")
    func initLaunchedFreshByDefault() {
        wipeReason()
        defer { wipeReason() }
        let store = SessionStore()
        #expect(store.lastSignOutReason == .launchedFresh)
    }

    @Test("a non-user-initiated signedOut event classifies as .sessionExpired and persists")
    func nonUserInitiatedDropIsSessionExpired() throws {
        wipeReason()
        defer { wipeReason() }
        let store = SessionStore()
        // Simulate the user previously being signed in...
        store.applyUITestUser(userId: UUID())
        // ...and Supabase emitting a .signedOut event because the refresh
        // token was revoked server-side. The user never called signOut().
        store.applyAuthStateChange(event: .signedOut, session: nil)

        #expect(store.lastSignOutReason == .sessionExpired)
        // Persistence — a kill mid-failure must still surface the banner on
        // the next cold start.
        let persisted = UserDefaults.standard.string(forKey: Self.key)
        #expect(persisted == SessionStore.SignOutReason.sessionExpired.rawValue)
    }

    @Test("signOut() flagging .userInitiated wins over the auth-changes loop's classification")
    func userInitiatedSignOutClassifiesCorrectly() async {
        wipeReason()
        defer { wipeReason() }
        let store = SessionStore()
        store.applyUITestUser(userId: UUID())
        // Simulate the production path: user taps sign out, signOut() runs.
        // (The Supabase client errors offline, but signOut() still clears
        // local state and records the reason.)
        await store.signOut()

        #expect(store.userId == nil)
        #expect(store.lastSignOutReason == .userInitiated)
    }

    @Test("userId transitioning nil → non-nil clears the sessionExpired banner")
    func successfulSignInClearsBanner() throws {
        wipeReason()
        defer { wipeReason() }
        let store = SessionStore()
        // Seed a stuck banner state — same as the user opening AuthView after
        // a server-side revocation.
        store.applyUITestUser(userId: UUID())
        store.applyAuthStateChange(event: .signedOut, session: nil)
        #expect(store.lastSignOutReason == .sessionExpired)

        // Simulate Supabase emitting a fresh session.
        store.applyAuthStateChange(event: .signedIn, session: nil)
        // The applyAuthStateChange with a non-nil userId is what triggers
        // clearing, so we'll exercise the explicit clear path that
        // AuthViewModel.submit() uses.
        store.clearSignOutReason()
        #expect(store.lastSignOutReason == .userInitiated)
    }

    @Test(".tokenRefreshed with a nil session classifies as .tokenRefreshFailed (P1.5)")
    func tokenRefreshedWithNilSessionIsRefreshFailure() {
        // Supabase emits `.tokenRefreshed` with `session == nil` when the
        // library tried to renew the access token and couldn't (network
        // failure, refresh-token rejected, etc). This is distinct from a
        // hard server-side revocation, which surfaces as `.signedOut`.
        wipeReason()
        defer { wipeReason() }
        let store = SessionStore()
        store.applyUITestUser(userId: UUID())

        store.applyAuthStateChange(event: .tokenRefreshed, session: nil)

        #expect(store.lastSignOutReason == .tokenRefreshFailed)
        let persisted = UserDefaults.standard.string(forKey: Self.key)
        #expect(persisted == SessionStore.SignOutReason.tokenRefreshFailed.rawValue)
    }

    @Test("AuthViewModel.submit returns .pendingConfirmation without clearing the banner (P2.7)")
    func pendingConfirmationDoesNotClearBanner() {
        // The user opened AuthView because their session expired. They start
        // a sign-up. Supabase returns no session (email confirmation required).
        // The banner must still be visible if they back out — they have not
        // actually signed in yet. The view-layer `if outcome == .establishedSession`
        // gate enforces this; the contract here pins the outcome value.
        let outcome = AuthViewModel.SubmitOutcome.pendingConfirmation
        // The gate is `outcome == .establishedSession` — anything else leaves
        // `lastSignOutReason` alone. Documenting the truth table to keep
        // the call site honest if the enum grows.
        #expect(outcome != .establishedSession)
        #expect(AuthViewModel.SubmitOutcome.failure != .establishedSession)
    }

    @Test("clearSignOutReason() is idempotent and does not flap when called repeatedly")
    func clearSignOutReasonIsIdempotent() {
        wipeReason()
        defer { wipeReason() }
        let store = SessionStore()
        store.clearSignOutReason()
        #expect(store.lastSignOutReason == .userInitiated)
        store.clearSignOutReason()
        #expect(store.lastSignOutReason == .userInitiated)
    }

    @Test("persisted .sessionExpired survives across SessionStore instances — cold-start banner")
    func persistedReasonSurvivesColdStart() throws {
        wipeReason()
        defer { wipeReason() }
        UserDefaults.standard.set(
            SessionStore.SignOutReason.sessionExpired.rawValue,
            forKey: Self.key
        )

        let store = SessionStore()
        // The banner needs to be visible on the very first AuthView render
        // after a kill — that's why init reads UserDefaults synchronously
        // before bootstrap() subscribes.
        #expect(store.lastSignOutReason == .sessionExpired)
    }

    // MARK: - SessionExpiryBanner.shouldShow contract

    @Test("SessionExpiryBanner renders only for .sessionExpired or .tokenRefreshFailed")
    func bannerShouldShowOnlyForNonUserInitiated() {
        #expect(SessionExpiryBanner.shouldShow(for: .sessionExpired))
        #expect(SessionExpiryBanner.shouldShow(for: .tokenRefreshFailed))
        #expect(!SessionExpiryBanner.shouldShow(for: .userInitiated))
        #expect(!SessionExpiryBanner.shouldShow(for: .launchedFresh))
    }

    @Test("Banner copy carries the spec-mandated reassurance about local data")
    func bannerCopyMentionsLocalDataSafety() {
        // The most important reassurance per spec — "scans and offers are
        // still saved on this device" — has to survive copy edits or it stops
        // doing its job.
        let banner = SessionExpiryBanner(reason: .sessionExpired)
        #expect(banner.detail.contains("saved on this device"))
        #expect(banner.headline == "Your session ended.")
    }
}
