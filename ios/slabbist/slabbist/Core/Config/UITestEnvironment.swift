import Foundation
import SwiftData
import OSLog

/// Test seam used by XCUITests to skip auth, isolate storage, and avoid
/// network calls. Activated by passing `--ui-tests` as a launch argument
/// (XCUITests can do this via `app.launchArguments.append("--ui-tests")`).
///
/// When active, the app:
///   * Boots into an in-memory SwiftData container so each test launches
///     with an empty store, no leftover state from prior runs.
///   * Auto-applies a synthetic signed-in user + matching `Store` row so
///     `LotsViewModel.resolve(...)` returns a usable view model immediately
///     (no real Supabase auth round-trip).
///   * Skips the `StoreHydrator` network kick so the lots tab doesn't sit
///     on "Setting up your store…" forever waiting for an HTTP call that
///     will never land.
///
/// The flag is read once at launch — flipping it mid-session is not
/// supported. Production code paths are unchanged when the flag is absent.
@MainActor
enum UITestEnvironment {
    /// Synthetic identifiers used across UI test launches. Stable so a
    /// test can reliably refer to "the test store" / "the test user"
    /// without hard-coding a fresh UUID per test.
    static let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let storeId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let storeName = "Test Store"

    /// True when the host process was launched with `--ui-tests`. Reading
    /// `ProcessInfo.processInfo.arguments` is cheap and the value never
    /// changes during a process lifetime, so we don't bother caching it.
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-tests")
    }

    /// Optional toggles tests can layer on top of `--ui-tests` to drive
    /// specific app states. All read once at launch — see `isActive`.
    enum Flag: String {
        /// Pre-seed the in-memory store with one open lot named "Sample
        /// Lot" so a test can deep-link into it without first creating
        /// one via the UI. Useful for isolating downstream flows.
        case seedSampleLot = "--ui-tests-seed-sample-lot"

        /// Pre-seed a validated scan stuck in `noData` (Pokemon Price
        /// Tracker found no comp) inside the sample lot. Lets the manual-
        /// price flow be tested without driving the cert-lookup +
        /// comp-fetch network pipeline. Implies `seedSampleLot`.
        case seedNoCompScan = "--ui-tests-seed-no-comp-scan"
    }

    static func isFlagSet(_ flag: Flag) -> Bool {
        ProcessInfo.processInfo.arguments.contains(flag.rawValue)
    }

    /// Returns the `ModelContainer` the app should use for this launch.
    /// Switches to in-memory under UI tests so each run starts clean.
    static func resolveModelContainer() -> ModelContainer {
        if isActive {
            return AppModelContainer.inMemory()
        }
        return AppModelContainer.shared
    }

    /// Bootstraps the synthetic signed-in state when running under UI
    /// tests. Idempotent — calling it twice with the same context is a
    /// no-op because the synthetic `Store` is keyed on its fixed UUID.
    static func bootstrapIfActive(
        session: SessionStore,
        hydrator: StoreHydrator,
        container: ModelContainer
    ) {
        guard isActive else { return }
        // Use the container's mainContext (the same one the views read
        // from via `@Environment(\.modelContext)`). Spinning up a fresh
        // `ModelContext(container)` here works against in-memory
        // SwiftData containers but its inserts can race the views'
        // `@Query` snapshots — the seeded data is then briefly invisible
        // to the very view trying to render it.
        let context = container.mainContext
        ensureStoreExists(in: context)
        if isFlagSet(.seedSampleLot) || isFlagSet(.seedNoCompScan) {
            seedSampleLotIfMissing(in: context)
        }
        if isFlagSet(.seedNoCompScan) {
            seedNoCompScanIfMissing(in: context)
        }
        session.applyUITestUser(userId: userId)
        // Pre-stamp the hydrator as ready so `LotsListView.prepare()`
        // doesn't sit on `Setting up your store…` waiting for a network
        // call that will never land in the simulator under tests.
        hydrator.markReadyForUITests(userId: userId)
        log.info("UI test bootstrap applied (userId=\(userId, privacy: .public), storeId=\(storeId, privacy: .public))")
    }

    private static func ensureStoreExists(in context: ModelContext) {
        let id = storeId
        var descriptor = FetchDescriptor<Store>(predicate: #Predicate<Store> { $0.id == id })
        descriptor.fetchLimit = 1
        if (try? context.fetch(descriptor).first) != nil { return }
        let store = Store(id: storeId, name: storeName, ownerUserId: userId, createdAt: Date())
        context.insert(store)
        try? context.save()
    }

    private static func seedSampleLotIfMissing(in context: ModelContext) {
        let lotName = sampleLotName
        var descriptor = FetchDescriptor<Lot>(predicate: #Predicate<Lot> { $0.name == lotName })
        descriptor.fetchLimit = 1
        if (try? context.fetch(descriptor).first) != nil { return }
        let now = Date()
        let lot = Lot(
            id: sampleLotId,
            storeId: storeId,
            createdByUserId: userId,
            name: lotName,
            createdAt: now,
            updatedAt: now
        )
        context.insert(lot)
        try? context.save()
    }

    /// Inserts a synthetic scan + identity that mimics the post-cert-
    /// lookup, no-comp end state — `gradedCardIdentityId` is set, the
    /// scan is `.validated`, and `compFetchState` is `.noData`. That
    /// combination is what surfaces the "Set manual price" CTA on
    /// `ScanDetailView`, which is what the manual-price test wants to
    /// exercise without driving the live cert-lookup pipeline.
    private static func seedNoCompScanIfMissing(in context: ModelContext) {
        let certNumber = sampleNoCompCert
        var scanDescriptor = FetchDescriptor<Scan>(
            predicate: #Predicate<Scan> { $0.certNumber == certNumber }
        )
        scanDescriptor.fetchLimit = 1
        if (try? context.fetch(scanDescriptor).first) != nil { return }

        let identityId = sampleIdentityId
        var identityDescriptor = FetchDescriptor<GradedCardIdentity>(
            predicate: #Predicate<GradedCardIdentity> { $0.id == identityId }
        )
        identityDescriptor.fetchLimit = 1
        if (try? context.fetch(identityDescriptor).first) == nil {
            context.insert(GradedCardIdentity(
                id: identityId,
                game: "pokemon",
                language: "en",
                setName: "Test Set",
                cardNumber: "1",
                cardName: "Test Card",
                variant: nil,
                year: 2024
            ))
        }

        let now = Date()
        let scan = Scan(
            id: UUID(),
            storeId: storeId,
            lotId: sampleLotId,
            userId: userId,
            grader: .PSA,
            certNumber: certNumber,
            grade: "10",
            gradedCardIdentityId: identityId,
            status: .validated,
            createdAt: now,
            updatedAt: now
        )
        scan.compFetchState = CompFetchState.noData.rawValue
        scan.compFetchedAt = now
        context.insert(scan)
        try? context.save()
    }

    static let sampleLotId = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    static let sampleLotName = "Sample Lot"
    static let sampleNoCompCert = "11223344"
    static let sampleIdentityId = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    private static let log = Logger(subsystem: "com.slabbist.uitests", category: "bootstrap")
}
