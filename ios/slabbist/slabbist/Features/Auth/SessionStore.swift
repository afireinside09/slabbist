import Foundation
import Observation
import Supabase
import OSLog

@Observable
@MainActor
final class SessionStore {
    private(set) var userId: UUID?
    private(set) var isLoading = false

    /// Why the user is sitting on `AuthView` right now. Drives the
    /// `SessionExpiryBanner` so a non-user-initiated drop (token refresh
    /// failure, server-side revocation) doesn't look like the user signed
    /// themselves out. Persisted across launches so a kill mid-failure
    /// still surfaces the banner on next cold start.
    enum SignOutReason: String, Equatable, Codable {
        case userInitiated         // explicit signOut() call
        case sessionExpired        // refresh-token failure / server revocation
        case tokenRefreshFailed    // reserved: distinct surface for future refinement
        case launchedFresh         // first launch / persisted session loaded clean
    }

    /// Read by `SessionExpiryBanner` on `AuthView`. Note: there is conceptual
    /// overlap with A5's `OutboxStatus.authState` (which drives the
    /// `SyncStatusPill` copy while signed in). Both signals are derived from
    /// Supabase auth events but serve different surfaces — pill while signed
    /// in, banner while signed out — and dedupe is intentionally out of
    /// scope for F1. See P2.12 in the Wave 2B review.
    private(set) var lastSignOutReason: SignOutReason

    private let client: SupabaseClient
    private var authTask: Task<Void, Never>?
    /// Set true when `signOut()` is invoked and consumed by the auth-changes
    /// loop on the next `.signedOut` event so we don't misclassify a
    /// user-initiated sign-out as `.sessionExpired`.
    private var userInitiatedSignOut: Bool = false

    private static let signOutReasonDefaultsKey = "slabbist.signOutReason.v1"

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
        // Read persisted reason BEFORE bootstrap subscribes so a banner that
        // was set on the prior run is visible on the first AuthView render.
        self.lastSignOutReason = Self.loadPersistedReason()
    }

    func bootstrap() {
        authTask?.cancel()
        let client = self.client
        authTask = Task { [weak self] in
            // `emitLocalSessionAsInitialSession` means the stream fires
            // `.initialSession` with the persisted session on subscribe, so
            // we don't need a separate `client.auth.session` read to seed
            // `userId`. Auto-refresh follows up with `.tokenRefreshed` /
            // `.signedOut` if the initial session was expired.
            for await change in client.auth.authStateChanges {
                if change.event == .initialSession,
                   change.session?.isExpired == true {
                    continue
                }
                self?.applyAuthStateChange(event: change.event, session: change.session)
            }
        }
    }

    /// Applies a single auth-state transition to the local state machine.
    /// Pulled out of the loop so unit tests can drive sign-out classification
    /// without spinning a real `authStateChanges` stream.
    func applyAuthStateChange(event: AuthChangeEvent, session: Session?) {
        let previousUserId = self.userId
        let nextUserId = session?.user.id
        self.userId = nextUserId

        // userId transitioning nil -> non-nil resets the banner: whether the
        // sign-in completed because the user typed credentials or because the
        // token refreshed cleanly, we no longer need to surface why the user
        // was bounced.
        if previousUserId == nil, nextUserId != nil {
            updateSignOutReason(.userInitiated)
            userInitiatedSignOut = false
            return
        }

        // userId went away. Decide whether the drop was self-inflicted, and
        // if not, classify by Supabase's auth-change event:
        //   - `.tokenRefreshed` with `session == nil` is the refresh-failure
        //     signal — the library tried to renew and couldn't.
        //   - `.signedOut` (without `userInitiatedSignOut`) is server-side
        //     revocation or persisted-session expiry on cold start.
        // Both end the user at AuthView; the type-level split lets future
        // copy/diagnostics differ without a migration.
        if previousUserId != nil, nextUserId == nil {
            if userInitiatedSignOut {
                userInitiatedSignOut = false
                updateSignOutReason(.userInitiated)
            } else if event == .tokenRefreshed {
                updateSignOutReason(.tokenRefreshFailed)
            } else {
                updateSignOutReason(.sessionExpired)
            }
        }
    }

    /// Clears the Supabase auth session and resets local user state.
    /// No-op (still returns cleanly) when the caller is already signed out.
    func signOut() async {
        userInitiatedSignOut = true
        let client = self.client
        do {
            try await client.auth.signOut()
        } catch {
            AppLog.auth.warning("Supabase signOut failed: \(error.localizedDescription, privacy: .public)")
        }
        // If the auth-changes loop hasn't yet observed the `.signedOut` event
        // (or won't, because the client never raised one in offline cases),
        // record the reason directly so the banner doesn't mis-fire on the
        // next AuthView render.
        if self.userId != nil {
            userInitiatedSignOut = false
            self.userId = nil
            updateSignOutReason(.userInitiated)
        }
    }

    var isSignedIn: Bool { userId != nil }

    /// Called by `AuthViewModel.submit()` immediately after a successful
    /// sign-in/sign-up so the banner clears even before the auth-changes
    /// stream gets around to firing `.signedIn`. Idempotent.
    func clearSignOutReason() {
        guard lastSignOutReason != .userInitiated else { return }
        updateSignOutReason(.userInitiated)
    }

    /// XCUITest seam: short-circuit auth so the test harness lands inside
    /// the post-sign-in app shell without hitting Supabase. Production
    /// code never calls this — it is gated by `UITestEnvironment.isActive`
    /// in `slabbistApp`.
    func applyUITestUser(userId: UUID) {
        authTask?.cancel()
        self.userId = userId
    }

    // MARK: - Persistence

    private func updateSignOutReason(_ reason: SignOutReason) {
        lastSignOutReason = reason
        Self.persistReason(reason)
    }

    private static func loadPersistedReason() -> SignOutReason {
        guard
            let raw = UserDefaults.standard.string(forKey: signOutReasonDefaultsKey),
            let reason = SignOutReason(rawValue: raw)
        else {
            return .launchedFresh
        }
        return reason
    }

    private static func persistReason(_ reason: SignOutReason) {
        UserDefaults.standard.set(reason.rawValue, forKey: signOutReasonDefaultsKey)
    }
}
