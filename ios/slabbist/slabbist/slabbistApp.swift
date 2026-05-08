import SwiftUI
import SwiftData
import OSLog
import UIKit

@main
struct SlabbistApp: App {
    @State private var session = SessionStore()
    @State private var hydrator = StoreHydrator()

    /// Resolved once at app start. Under XCUITests this swaps to an
    /// in-memory container so every test launch starts with an empty
    /// SwiftData store; in production it returns the file-backed shared
    /// container exactly as before.
    private let modelContainer: ModelContainer = UITestEnvironment.resolveModelContainer()

    init() {
        Self.verifyCustomFontsLoaded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(hydrator)
                .onAppear {
                    if UITestEnvironment.isActive {
                        // UI test harness: skip Supabase auth + hydrator.
                        // Bootstrap synthetic user/store so the post-auth
                        // shell is reachable without a network round-trip.
                        UITestEnvironment.bootstrapIfActive(
                            session: session,
                            hydrator: hydrator,
                            container: modelContainer
                        )
                    } else {
                        session.bootstrap()
                    }
                }
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)
    }

    private static let designLog = Logger(
        subsystem: "com.slabbist.designsystem",
        category: "fonts"
    )

    private static func verifyCustomFontsLoaded() {
        let required = ["InstrumentSerif-Regular", "InstrumentSerif-Italic"]
        for name in required where UIFont(name: name, size: 10) == nil {
            designLog.warning("Custom font \(name, privacy: .public) failed to load — bundle or UIAppFonts registration is broken.")
        }
    }
}

private struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.isSignedIn {
            RootTabView()
        } else {
            AuthView()
        }
    }
}
