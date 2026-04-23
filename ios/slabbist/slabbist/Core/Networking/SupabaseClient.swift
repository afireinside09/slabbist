import Foundation
import Supabase

/// A single process-wide Supabase client. Holds the auth session and exposes
/// the Postgrest + Auth surfaces we need app-wide.
final class AppSupabase {
    static let shared = AppSupabase()

    let client: SupabaseClient

    private init() {
        self.client = SupabaseClient(
            supabaseURL: AppEnvironment.supabaseURL,
            supabaseKey: AppEnvironment.supabaseAnonKey
        )
    }
}
