import Foundation
import Testing
@testable import slabbist

@Suite("AppEnvironment")
struct AppEnvironmentTests {
    @Test("supabaseURL resolves to a non-nil URL")
    func urlNotNil() {
        _ = AppEnvironment.supabaseURL
    }

    @Test("supabaseKey is non-empty")
    func keyNotEmpty() {
        #expect(!AppEnvironment.supabaseKey.isEmpty)
    }

    @Test("supabaseAnonKey mirrors supabaseKey")
    func anonKeyAlias() {
        #expect(AppEnvironment.supabaseAnonKey == AppEnvironment.supabaseKey)
    }

    @Test("isLocalStack reflects the resolved URL host")
    func isLocalStackFlag() {
        let host = AppEnvironment.supabaseURL.host ?? ""
        let expected = (host == "127.0.0.1" || host == "localhost")
        #expect(AppEnvironment.isLocalStack == expected)
    }
}
