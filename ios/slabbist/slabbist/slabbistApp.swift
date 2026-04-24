import SwiftUI
import SwiftData
import OSLog
import UIKit

@main
struct SlabbistApp: App {
    @State private var session = SessionStore()
    @State private var hydrator = StoreHydrator()

    init() {
        Self.verifyCustomFontsLoaded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(hydrator)
                .onAppear { session.bootstrap() }
                .preferredColorScheme(.dark)
        }
        .modelContainer(AppModelContainer.shared)
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
