import Foundation
import Observation
import OSLog
import Supabase

@Observable
@MainActor
final class AuthViewModel {
    enum Mode { case signIn, signUp }

    var email: String = ""
    var password: String = ""
    var storeName: String = ""
    var mode: Mode = .signIn
    var errorMessage: String?
    var isSubmitting = false

    /// Set to the just-signed-up address when Supabase is configured to
    /// require email confirmation (signUp returns no session). The view
    /// swaps to the "check your email" screen while this is non-nil.
    var pendingConfirmationEmail: String?

    private let auth: AuthService

    init(auth: AuthService = AuthService()) {
        self.auth = auth
    }

    /// Result of a single submit() call. `establishedSession` means Supabase
    /// returned a session the SessionStore will see — used by the view to
    /// decide whether to clear the expiry banner. `pendingConfirmation` is
    /// sign-up with a confirm-email gate (no session yet); `failure` is a
    /// thrown error already surfaced via `errorMessage`.
    enum SubmitOutcome: Equatable {
        case establishedSession
        case pendingConfirmation
        case failure
    }

    @discardableResult
    func submit() async -> SubmitOutcome {
        guard !isSubmitting else { return .failure }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            switch mode {
            case .signIn:
                _ = try await auth.signIn(email: email, password: password)
                return .establishedSession
            case .signUp:
                let metadata: [String: AnyJSON] = storeName.isEmpty
                    ? [:]
                    : ["store_name": .string(storeName)]
                let response = try await auth.signUp(
                    email: email,
                    password: password,
                    metadata: metadata
                )
                // No session means the project requires email confirmation.
                // SessionStore will auto-redirect once the user confirms and
                // signs in; until then, show the "check your email" screen.
                if response.session == nil {
                    pendingConfirmationEmail = email
                    password = ""
                    return .pendingConfirmation
                }
                return .establishedSession
            }
        } catch {
            errorMessage = error.localizedDescription
            AppLog.auth.error("auth submit failed: \(error.localizedDescription, privacy: .public)")
            return .failure
        }
    }

    func toggleMode() {
        mode = (mode == .signIn) ? .signUp : .signIn
        errorMessage = nil
    }

    /// Leave the confirmation screen and land on sign-in with the address
    /// pre-filled so the user can sign in as soon as they've clicked the link.
    func backToSignIn() {
        if let confirmed = pendingConfirmationEmail {
            email = confirmed
        }
        pendingConfirmationEmail = nil
        password = ""
        storeName = ""
        errorMessage = nil
        mode = .signIn
    }
}
