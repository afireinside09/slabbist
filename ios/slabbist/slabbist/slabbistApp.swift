import SwiftUI
import SwiftData
import OSLog
import UIKit

@main
struct SlabbistApp: App {
    @State private var session = SessionStore()
    @State private var hydrator = StoreHydrator()
    @State private var reachability = Reachability()
    @State private var tabRouter = TabRouter()
    @State private var status: OutboxStatus
    @State private var kicker: OutboxKicker
    private let drainer: OutboxDrainer
    /// Long-lived consumer that applies drainer status updates to
    /// `OutboxStatus` in strict emission order. Held for the app's lifetime.
    private let statusApplyTask: Task<Void, Never>
    /// A2: failures-sheet bridge built once at app init and injected via
    /// environment so `SyncStatusPill` can present the review sheet
    /// without importing the drainer directly.
    private let failureBridge: OutboxFailureBridge

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

        // The drainer (an actor) emits status updates in order, but the old
        // sink spawned a fresh unordered `Task { @MainActor }` per update —
        // MainActor doesn't guarantee those run in creation order, so a later
        // "0 pending, idle" could apply before an earlier "5 pending,
        // draining", leaving the sync pill stuck showing stale counts or
        // "draining" forever. Funnel every update through one AsyncStream
        // drained by a single consumer so they apply strictly in order.
        let (statusStream, statusContinuation) =
            AsyncStream<OutboxDrainer.StatusUpdate>.makeStream()

        let drainer = OutboxDrainer(
            modelContainer: container,
            repositories: repos,
            clock: SystemClock(),
            statusSink: { update in statusContinuation.yield(update) }
        )
        self.drainer = drainer
        self._status = State(initialValue: statusBox)
        self.statusApplyTask = Task { @MainActor in
            for await update in statusStream {
                statusBox.update(
                    pendingCount: update.pendingCount,
                    failedCount: update.failedCount,
                    isDraining: update.isDraining
                )
                if let isPaused = update.isPaused {
                    statusBox.setPaused(
                        isPaused,
                        reason: update.lastError,
                        authState: update.authState
                    )
                }
            }
        }
        // A4: `kick()` itself sets `kickPending` when it lands during a
        // drain pass — see `OutboxDrainer.drainOnce`. The kicker just
        // forwards; the drainer owns the coalesce semantics.
        let liveKicker = OutboxKicker { await drainer.kick() }
        self._kicker = State(initialValue: liveKicker)
        // A2: failures-sheet bridge. Retry kicks the drainer through the
        // kicker so producers / lifecycle hooks share one entry point.
        self.failureBridge = OutboxFailureBridge(
            load: { await drainer.listFailed() },
            retry: { id in
                await drainer.retryFailed(id: id)
                await drainer.kick()
            },
            discard: { id in
                await drainer.discardFailed(id: id)
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(hydrator)
                .environment(reachability)
                .environment(tabRouter)
                .environment(status)
                .environment(kicker)
                .environment(failureBridge)
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
                    // Sign-in (or session restored from keychain) → unpause
                    // then kick so that a 401-paused queue self-heals as soon
                    // as supabase-swift auto-refreshes the token or the user
                    // signs in manually.
                    guard newId != nil else { return }
                    let drainer = self.drainer
                    Task.detached(priority: .utility) {
                        await drainer.unpause()
                        await drainer.kick()
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
