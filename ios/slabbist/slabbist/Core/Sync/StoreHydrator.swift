import Foundation
import OSLog
import SwiftData
import Observation

/// Pulls the signed-in user's `stores` rows from Supabase and upserts
/// them into the local SwiftData store. The server-side
/// `handle_new_user` trigger seeds a Store row on signup, but the iOS
/// app only reads Stores from SwiftData — without this hydration the
/// Lots/Scan flows silently defer because `LotsViewModel.resolve`
/// never finds a local Store.
///
/// Idempotent per user: once a userId is hydrated, repeat calls in
/// the same session short-circuit. Sign-out resets state so the next
/// sign-in re-hydrates.
@MainActor
@Observable
final class StoreHydrator {
    enum State: Equatable {
        case idle
        case running
        case ready(hydratedUserId: UUID)
        case failed(message: String)
    }

    private(set) var state: State = .idle

    private let container: ModelContainer
    private let repository: any StoreRepository
    private var inFlight: Task<Void, Never>?

    /// Takes `ModelContainer` (Sendable, not MainActor-isolated) so the
    /// init is callable from any context. The MainActor-only
    /// `mainContext` is pulled lazily inside MainActor methods.
    ///
    /// `container` defaults to `nil` and resolves to
    /// `AppModelContainer.shared` inside the MainActor-isolated init body
    /// — Swift 6 evaluates default-arg expressions in nonisolated context,
    /// so referencing the MainActor-isolated `shared` directly as a
    /// default would warn under `-default-isolation=MainActor`.
    init(
        container: ModelContainer? = nil,
        repository: any StoreRepository = SupabaseStoreRepository()
    ) {
        self.container = container ?? AppModelContainer.shared
        self.repository = repository
    }

    private var context: ModelContext { container.mainContext }

    /// Trigger on sign-in via `.task(id: session.userId)`. Safe to call
    /// repeatedly — a second call for the already-hydrated user is a
    /// no-op, and concurrent callers await the in-flight task.
    func hydrateIfNeeded(userId: UUID) async {
        if case .ready(let current) = state, current == userId { return }
        if let existing = inFlight {
            await existing.value
            return
        }
        state = .running
        let task = Task { await self.performHydration(userId: userId) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Call on sign-out so the next sign-in re-hydrates (e.g. for a
    /// different user on the same device).
    func reset() {
        inFlight?.cancel()
        inFlight = nil
        state = .idle
    }

    /// XCUITest seam: stamp the hydrator as already complete for a
    /// synthetic user so `LotsListView.prepare()` can skip the network
    /// call entirely. Production code never invokes this; it is gated by
    /// `UITestEnvironment.isActive` in `slabbistApp`.
    func markReadyForUITests(userId: UUID) {
        inFlight?.cancel()
        inFlight = nil
        state = .ready(hydratedUserId: userId)
    }

    private func performHydration(userId: UUID) async {
        do {
            let dtos = try await repository.listForCurrentUser(page: .default)
            try upsertAll(dtos)
            state = .ready(hydratedUserId: userId)
            AppLog.stores.info("hydration ok user=\(userId, privacy: .public) rows=\(dtos.count, privacy: .public)")
        } catch {
            state = .failed(message: error.localizedDescription)
            AppLog.stores.error("hydration failed user=\(userId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func upsertAll(_ dtos: [StoreDTO]) throws {
        for dto in dtos {
            let storeId = dto.id
            var descriptor = FetchDescriptor<Store>(
                predicate: #Predicate<Store> { $0.id == storeId }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                existing.apply(dto)
            } else {
                context.insert(Store(dto: dto))
            }
        }
        try context.save()
    }
}
