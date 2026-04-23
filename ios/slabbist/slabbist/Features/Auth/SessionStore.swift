import Foundation
import Observation
import Supabase

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
            for await change in client.auth.authStateChanges {
                await MainActor.run {
                    self?.userId = change.session?.user.id
                }
            }
        }

        Task { [weak self] in
            let session = try? await client.auth.session
            await MainActor.run {
                self?.userId = session?.user.id
            }
        }
    }

    var isSignedIn: Bool { userId != nil }
}
