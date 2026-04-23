import Foundation
import Supabase

/// Reusable facade over Supabase auth. Any caller — view model,
/// background task, outbox worker, CLI script — can depend on this
/// instead of reaching into `AppSupabase.shared.client.auth` directly.
///
/// This layer intentionally does **not** own session state for the UI;
/// `SessionStore` (Features/Auth) remains the observable source of
/// truth for the view hierarchy. `AuthService` is for actions and
/// one-shot reads.
///
/// Errors are normalized through `SupabaseError.map(_:)`.
nonisolated struct AuthService: Sendable {
    let client: SupabaseClient

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
    }

    // MARK: - Sign in / sign up / sign out

    @discardableResult
    func signIn(email: String, password: String) async throws -> Session {
        do {
            return try await client.auth.signIn(email: email, password: password)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    @discardableResult
    func signUp(
        email: String,
        password: String,
        metadata: [String: AnyJSON] = [:]
    ) async throws -> AuthResponse {
        do {
            return try await client.auth.signUp(
                email: email,
                password: password,
                data: metadata.isEmpty ? nil : metadata
            )
        } catch {
            throw SupabaseError.map(error)
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            throw SupabaseError.map(error)
        }
    }

    // MARK: - Session

    /// Current session if one exists. Returns `nil` when the user is
    /// signed out or the persisted session has expired beyond refresh.
    func currentSession() async -> Session? {
        try? await client.auth.session
    }

    func currentUserId() async -> UUID? {
        await currentSession()?.user.id
    }

    @discardableResult
    func refreshSession() async throws -> Session {
        do {
            return try await client.auth.refreshSession()
        } catch {
            throw SupabaseError.map(error)
        }
    }

    // MARK: - Password reset

    func sendPasswordReset(email: String, redirectTo: URL? = nil) async throws {
        do {
            try await client.auth.resetPasswordForEmail(email, redirectTo: redirectTo)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    // MARK: - Metadata

    @discardableResult
    func updateUserMetadata(_ metadata: [String: AnyJSON]) async throws -> User {
        do {
            return try await client.auth.update(user: UserAttributes(data: metadata))
        } catch {
            throw SupabaseError.map(error)
        }
    }

    // MARK: - State stream

    /// Auth state changes stream. Wraps `client.auth.authStateChanges`
    /// so observers only need to know about `AuthService`.
    var stateChanges: AsyncStream<AuthStateChangeEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await change in client.auth.authStateChanges {
                    continuation.yield(AuthStateChangeEvent(event: change.event, session: change.session))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Snapshot of an auth state change suitable for passing across tasks
/// and across module boundaries without leaking SDK internals.
nonisolated struct AuthStateChangeEvent: Sendable {
    let event: AuthChangeEvent
    let session: Session?

    var userId: UUID? { session?.user.id }
}
