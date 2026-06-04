import Foundation

/// App-wide environment configuration (Supabase URL, keys).
///
/// Resolution order for every value:
///   1. Process-environment variable (Xcode scheme → "Arguments" tab, or
///      inherited from the parent shell when Xcode is launched via
///      `open …` with direnv active — this is how `.envrc` at the repo
///      root flows in during local development).
///   2. `Info.plist` entry with the same name (populated at build time
///      from `Secrets.xcconfig` for archive / CI builds — see
///      `ios/slabbist/Config/Secrets.xcconfig.example`).
///   3. Hard-coded local-stack default (Supabase CLI's public demo
///      values — safe to commit, only usable against `supabase start`).
///
/// Rename note: Supabase is migrating `SUPABASE_ANON_KEY` →
/// `SUPABASE_PUBLISHABLE_KEY` (both names refer to the same JWT). We
/// prefer the new name but still honor the legacy one so existing
/// scheme args / CI configs keep working.
nonisolated enum AppEnvironment {
    static let supabaseURL: URL = {
        if let raw = lookup("SUPABASE_URL"), let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://127.0.0.1:54321")!
    }()

    static let supabaseKey: String = {
        for name in ["SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY"] {
            if let key = lookup(name), !key.isEmpty { return key }
        }
        // Local-stack demo anon key (baked into the Supabase CLI — public).
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    }()

    /// Back-compat alias. Prefer `supabaseKey` for new call sites.
    static var supabaseAnonKey: String { supabaseKey }

    /// Whether the resolved URL points at a local `supabase start` stack.
    /// Useful for disabling telemetry / production-only behavior in dev.
    static var isLocalStack: Bool {
        let host = supabaseURL.host ?? ""
        return host == "127.0.0.1" || host == "localhost"
    }

    /// eBay Partner Network campaign ID. Empty string when unset, in
    /// which case affiliate-link rewriting is skipped (URLs open raw).
    static let epnCampaignID: String = lookup("EPN_CAMPAIGN_ID") ?? ""

    /// Free-form tracking tag appended as `customid` on affiliate links.
    /// Defaults to "slabbist-ios" so click reports stay attributable
    /// even if the build forgets to set it.
    static let epnCustomID: String = {
        if let value = lookup("EPN_CUSTOM_ID"), !value.isEmpty { return value }
        return "slabbist-ios"
    }()

    /// impact.com base tracking URL for the TCGplayer campaign,
    /// "https://partner.tcgplayer.com/c/{account}/{ad}/{campaign}". The app
    /// appends `?subId1=<surface>&u=<encoded product url>` per card. Affiliate
    /// links are public (embedded in every outbound tap), so the account's
    /// live tracking link is baked in as the default — the buttons monetize
    /// with zero setup. Override via `TCGPLAYER_IMPACT_BASE_URL` (e.g. campaign
    /// rotation). An empty value makes `TCGPlayerAffiliateLink` open raw
    /// tcgplayer.com links instead.
    static let tcgplayerImpactBaseURL: String = {
        if let value = lookup("TCGPLAYER_IMPACT_BASE_URL"), !value.isEmpty { return value }
        return "https://partner.tcgplayer.com/c/6098165/1830156/21018"
    }()

    private static func lookup(_ name: String) -> String? {
        if let raw = ProcessInfo.processInfo.environment[name], !raw.isEmpty {
            return raw
        }
        if let raw = Bundle.main.object(forInfoDictionaryKey: name) as? String,
           !raw.isEmpty {
            return raw
        }
        return nil
    }
}
