import Testing
import Foundation
@testable import slabbist

@Suite("SessionStore sign-out")
@MainActor
struct SessionStoreSignOutTests {
    @Test("signOut() exists and returns without throwing when already signed out")
    func signOutIsCallableWhenAlreadySignedOut() async {
        let store = SessionStore()
        // Not bootstrap()'d — userId is nil. signOut() should be a no-op.
        await store.signOut()
        #expect(store.userId == nil)
        #expect(store.isSignedIn == false)
    }
}
