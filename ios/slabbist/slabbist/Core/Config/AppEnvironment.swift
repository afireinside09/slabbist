import Foundation

/// App-wide environment configuration (Supabase URL, keys, etc.).
///
/// **Plan 1 (walking skeleton) defaults** to the local Supabase stack
/// spun up by `supabase start` in the monorepo root. The local-stack
/// anon key is a public demo value baked into the Supabase CLI, so
/// hardcoding it here is safe.
///
/// **Overrides:** values can be overridden at launch via
/// `SUPABASE_URL` and `SUPABASE_ANON_KEY` process-environment
/// variables (e.g. set via Xcode's scheme arguments or CI). Later
/// plans will add xcconfig-based per-environment injection once
/// staging/prod environments exist.
enum AppEnvironment {
    static let supabaseURL: URL = {
        if let raw = ProcessInfo.processInfo.environment["SUPABASE_URL"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://127.0.0.1:54321")!
    }()

    static let supabaseAnonKey: String = {
        if let key = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"],
           !key.isEmpty {
            return key
        }
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    }()
}
