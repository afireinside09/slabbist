import SwiftUI
import SwiftData

@main
struct SlabbistApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .onAppear { session.bootstrap() }
        }
        .modelContainer(AppModelContainer.shared)
    }
}

private struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.isSignedIn {
            LotsListView()
        } else {
            AuthView()
        }
    }
}
