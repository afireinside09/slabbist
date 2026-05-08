import SwiftUI
import SwiftData
import OSLog
import UIKit

@main
struct SlabbistApp: App {
    @State private var session = SessionStore()
    @State private var hydrator = StoreHydrator()
    @State private var reachability = Reachability()
    @State private var status: OutboxStatus
    @State private var kicker: OutboxKicker
    private let drainer: OutboxDrainer

    /// Resolved once at app start. Under XCUITests this swaps to an
    /// in-memory container so every test launch starts with an empty
    /// SwiftData store; in production it returns the file-backed shared
    /// container exactly as before.
    ///
    /// `static let` so the single resolved instance is shared between
    /// the stored-property initializer (used by `.modelContainer(...)`)
    /// and the `App.init()` body (used to build `OutboxDrainer`).
    private static let sharedModelContainer: ModelContainer = UITestEnvironment.resolveModelContainer()
    private let modelContainer: ModelContainer = sharedModelContainer

    @Environment(\.scenePhase) private var scenePhase

    init() {
        Self.verifyCustomFontsLoaded()

        let container = Self.sharedModelContainer
        let repos = AppRepositories.live()
        let statusBox = OutboxStatus()

        let drainer = OutboxDrainer(
            modelContainer: container,
            repositories: repos,
            clock: SystemClock(),
            statusSink: { update in
                Task { @MainActor in
                    statusBox.update(
                        pendingCount: update.pendingCount,
                        isDraining: update.isDraining
                    )
                    if let isPaused = update.isPaused {
                        statusBox.setPaused(isPaused, reason: update.lastError)
                    }
                }
            }
        )
        self.drainer = drainer
        self._status = State(initialValue: statusBox)
        self._kicker = State(initialValue: OutboxKicker { await drainer.kick() })
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(hydrator)
                .environment(reachability)
                .environment(status)
                .environment(kicker)
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
                        reachability.start()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active { kicker.kick() }
                }
                .onChange(of: reachability.status) { _, newStatus in
                    if newStatus == .online { kicker.kick() }
                }
                .onChange(of: session.userId) { _, newId in
                    // Sign-in (or session restored from keychain) → kick.
                    // Sign-out (newId == nil) is handled by SessionStore;
                    // the drainer's pause flag (Task 10) clears separately.
                    if newId != nil { kicker.kick() }
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
