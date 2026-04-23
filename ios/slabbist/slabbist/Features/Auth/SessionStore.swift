import Foundation
import Observation
import Supabase
import OSLog

@Observable
@MainActor
final class SessionStore {
    private(set) var userId: UUID?
    private(set) var isLoading = false

    private let client: SupabaseClient
    private var authTask: Task<Void, Never>?

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
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
                self?.userId = change.session?.user.id
            }
        }
    }

    /// Clears the Supabase auth session and resets local user state.
    /// No-op (still returns cleanly) when the caller is already signed out.
    func signOut() async {
        let client = self.client
        do {
            try await client.auth.signOut()
        } catch {
            Self.log.warning("Supabase signOut failed: \(error.localizedDescription, privacy: .public)")
        }
        self.userId = nil
    }

    var isSignedIn: Bool { userId != nil }

    private static let log = Logger(subsystem: "com.slabbist.auth", category: "session")
}
