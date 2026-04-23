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

    private let client: SupabaseClient

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
    }

    func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            switch mode {
            case .signIn:
                _ = try await client.auth.signIn(email: email, password: password)
            case .signUp:
                let metadata: [String: AnyJSON] = storeName.isEmpty
                    ? [:]
                    : ["store_name": .string(storeName)]
                _ = try await client.auth.signUp(
                    email: email,
                    password: password,
                    data: metadata
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            AppLog.auth.error("auth submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func toggleMode() {
        mode = (mode == .signIn) ? .signUp : .signIn
        errorMessage = nil
    }
}
