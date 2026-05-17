// Features/Offers/OfferReviewView.swift
import SwiftUI
import SwiftData
import UIKit
import OSLog

/// The "ready to present" workbench. Operator presents the offer to the vendor
/// from this screen; bounces back if they negotiate; declines if they walk;
/// "Mark paid" hands off to Plan 3's commit flow (stubbed locally here — only
/// records the `accepted` state, no transaction yet).
struct OfferReviewView: View {
    let lot: Lot
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(OutboxKicker.self) private var kicker
    @Environment(\.dismiss) private var dismiss
    @Query private var scans: [Scan]
    @State private var paymentMethod: String = "cash"
    @State private var paymentReference: String = ""
    @State private var error: String?
    @State private var commitState: CommitState = .idle

    init(lot: Lot) {
        self.lot = lot
        let lotId = lot.id
        _scans = Query(filter: #Predicate<Scan> { $0.lotId == lotId },
                       sort: [SortDescriptor(\Scan.createdAt)])
    }

    /// State machine for the "Mark paid" CTA. Replaces the loose `isCommitting` +
    /// `commitError` pair so the view can model the synchronous-throw, in-flight,
    /// and stalled-sync paths as a single value the body switches over.
    /// `committing(startedAt:)` carries the moment the local repo write succeeded
    /// so the 10s timeout task can compute its own deadline deterministically.
    enum CommitState: Equatable {
        case idle
        case committing(startedAt: Date)
        case timedOut(startedAt: Date)
        case error(String)
    }

    /// 10 seconds is the bounded promise: by then the drainer has either landed
    /// the commit or the user has earned an explanation + an exit affordance.
    static let commitTimeout: Duration = .seconds(10)

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    totalCard
                    linesSection
                    paymentCard
                    if let error {
                        Text(error).font(SlabFont.sans(size: 13))
                            .foregroundStyle(AppColor.negative)
                            .accessibilityIdentifier("offer-review-error")
                    }
                    actionStack
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .navigationTitle("Offer review")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: lot.lotOfferState) { _, new in
            // The hydrator landing `.paid` resolves both .committing and .timedOut:
            // a late drain after the user has been shown "saved locally" still
            // completes the round-trip and we should leave the screen.
            guard new == LotOfferState.paid.rawValue else { return }
            switch commitState {
            case .committing, .timedOut:
                commitState = .idle
                dismiss()
            case .idle, .error:
                break
            }
        }
        .task(id: commitState) {
            // `.task(id:)` is cancelled automatically when `commitState`
            // changes, so when `.paid` lands mid-sleep SwiftUI sends
            // cancellation into the sleeper. The sleeper propagates
            // `CancellationError`; the helper swallows it at its boundary
            // and short-circuits without re-checking state. Cancellation is
            // the *design*, not a fortunate side effect of the re-read.
            await Self.runCommitTimeoutIfNeeded(
                state: { commitState },
                set: { commitState = $0 },
                sleeper: { try await Task.sleep(for: Self.commitTimeout) },
                announce: {
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "Offer saved locally. Sync pending."
                    )
                }
            )
        }
    }

    /// Pure-ish helper that drives the `.committing → .timedOut` transition.
    ///
    /// Cancellation contract:
    ///   - `sleeper` is expected to `throw CancellationError` when the parent
    ///     `.task(id:)` is cancelled (i.e. `commitState` changed under us
    ///     because `.paid` landed or the user navigated away).
    ///   - We catch `CancellationError` exactly at this boundary and return
    ///     without mutating state or announcing. Any other thrown error is a
    ///     bug in the injected sleeper — we still swallow it but the
    ///     post-sleep state re-check below is a belt-and-braces guard.
    ///   - The `if case .committing = state()` check after the sleep is the
    ///     load-bearing guarantee in case the announcer ran on the same
    ///     run-loop tick as a `.paid` resolution that pre-empted cancellation.
    ///
    /// `state` / `set` / `announce` are closures so tests can drive the
    /// transition without spinning a SwiftUI runtime; `sleeper` lets tests
    /// skip the 10s wait by passing a throw-free closure.
    static func runCommitTimeoutIfNeeded(
        state: @MainActor () -> CommitState,
        set: @MainActor (CommitState) -> Void,
        sleeper: () async throws -> Void,
        announce: @MainActor () -> Void
    ) async {
        guard case .committing(let started) = state() else { return }
        do {
            try await sleeper()
        } catch is CancellationError {
            return
        } catch {
            // Sleeper threw an unexpected error — fall through to the state
            // re-check rather than promoting `.timedOut` blindly. Logging the
            // surprise here keeps the failure visible without crashing the
            // commit flow.
            AppLog.app.warning("OfferReviewView timeout sleeper threw unexpectedly: \(error.localizedDescription, privacy: .public)")
        }
        if case .committing = state() {
            set(.timedOut(startedAt: started))
            announce()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Vendor")
            Text(lot.vendorNameSnapshot ?? "No vendor attached").slabTitle()
        }
    }

    private var totalCard: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                KickerLabel("Offer total")
                Text(formattedCents(totalBuyCents)).font(SlabFont.serif(size: 40))
                Text(marginSubtitle)
                    .font(SlabFont.mono(size: 12)).foregroundStyle(AppColor.dim)
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.l)
        }
    }

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Lines")
            SlabCard {
                VStack(spacing: 0) {
                    ForEach(scans, id: \.id) { scan in
                        if scan.id != scans.first?.id { SlabCardDivider() }
                        lineRow(scan)
                    }
                }
            }
        }
    }

    private func lineRow(_ scan: Scan) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(scan.grader.rawValue) \(scan.grade ?? "—") · \(scan.certNumber)")
                    .font(SlabFont.mono(size: 12)).foregroundStyle(AppColor.muted)
            }
            Spacer()
            Text(scan.buyPriceCents.map(formattedCents) ?? "—")
                .font(SlabFont.mono(size: 14, weight: .semibold))
                .foregroundStyle(scan.buyPriceOverridden ? AppColor.gold : AppColor.text)
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
    }

    private var paymentCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Payment")
            SlabCard {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Picker("Method", selection: $paymentMethod) {
                        ForEach(["cash", "check", "store_credit", "digital", "other"], id: \.self) {
                            Text($0.replacingOccurrences(of: "_", with: " ")).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("payment-method-picker")
                    TextField("Reference (check #, Venmo handle, …)", text: $paymentReference)
                        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
                        .accessibilityIdentifier("payment-reference-field")
                }
                .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.md)
            }
        }
    }

    private var actionStack: some View {
        VStack(spacing: Spacing.m) {
            primaryCTA

            commitStatusRow

            Button("Bounce back") {
                do {
                    try offerRepository().bounceBack(lot)
                    dismiss()
                } catch {
                    self.error = error.localizedDescription
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!secondaryActionsEnabled)
            .opacity(secondaryActionsEnabled ? 1.0 : 0.4)
            .accessibilityIdentifier("bounce-back")

            Button("Decline") {
                do { try offerRepository().decline(lot) }
                catch { self.error = error.localizedDescription }
            }
            .buttonStyle(SecondaryButtonStyle(role: .destructive))
            .disabled(!secondaryActionsEnabled)
            .opacity(secondaryActionsEnabled ? 1.0 : 0.4)
            .accessibilityIdentifier("decline-offer")
        }
    }

    /// Bounce-back and decline enqueue state transitions that conflict with
    /// an in-flight commit (the drainer would race two contradictory writes
    /// to the server). Lock them while the commit is in `.committing` or
    /// has timed out — in `.timedOut` the outbox is still trying to land
    /// the commit, so a decline now is doubly destructive.
    static func secondaryActionsEnabled(for state: CommitState) -> Bool {
        switch state {
        case .idle, .error: return true
        case .committing, .timedOut: return false
        }
    }

    private var secondaryActionsEnabled: Bool {
        Self.secondaryActionsEnabled(for: commitState)
    }

    /// The primary CTA flips identity per `commitState`. `.timedOut` reclaims
    /// the gold for "Go back" because Go back is now the path forward — leaving
    /// "Committing…" gold would dominate over the sync-pending explanation
    /// below and keep the user staring at the same screen.
    @ViewBuilder
    private var primaryCTA: some View {
        switch commitState {
        case .idle, .error:
            PrimaryGoldButton(
                title: "Mark paid",
                isEnabled: canMarkPaid
            ) {
                commit()
            }
            .accessibilityIdentifier("mark-paid")
        case .committing:
            PrimaryGoldButton(
                title: "Committing…",
                isEnabled: false
            ) { }
            .accessibilityIdentifier("mark-paid")
        case .timedOut:
            PrimaryGoldButton(
                title: "Go back",
                isEnabled: true
            ) {
                dismiss()
            }
            .accessibilityIdentifier("mark-paid")
        }
    }

    /// Single hairline-bordered row that replaces the inline conditional copy
    /// the old view kept above and below the CTA. Deliberately not a `SlabCard`
    /// (denser, inline) and read as one VoiceOver unit so the user hears the
    /// state — icon plus headline plus detail — as one announcement.
    @ViewBuilder
    private var commitStatusRow: some View {
        switch commitState {
        case .committing:
            // Spinner tint is `muted` not `gold` — the gold CTA already
            // carries the in-progress signal, and `.impeccable.md` mandates
            // one gold per screen. Two simultaneous golds would dilute the
            // CTA. (`lineRow`'s overridden-buy-price gold is in a different
            // visual region and predates this work.)
            statusRow(
                icon: "arrow.triangle.2.circlepath",
                iconTint: AppColor.muted,
                spinner: true,
                title: "Committing…",
                detail: "Talking to the server."
            )
            .accessibilityIdentifier("offer-review-sync-pending")
        case .timedOut:
            statusRow(
                icon: "checkmark.icloud",
                iconTint: AppColor.positive,
                spinner: false,
                title: "Saved locally — sync pending",
                detail: "Your offer is safe. We'll finish syncing once you're back online. The receipt will appear in this lot when it lands."
            )
            .accessibilityIdentifier("offer-review-timed-out")
        case .error(let msg):
            statusRow(
                icon: "exclamationmark.triangle",
                iconTint: AppColor.negative,
                spinner: false,
                title: "Couldn't commit",
                detail: msg
            )
            .accessibilityIdentifier("offer-review-commit-error")
        case .idle:
            EmptyView()
        }
    }

    private func statusRow(
        icon: String,
        iconTint: Color,
        spinner: Bool,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            ZStack {
                if spinner {
                    ProgressView()
                        .controlSize(.small)
                        .tint(iconTint)
                } else {
                    Image(systemName: icon)
                        .font(SlabFont.sans(size: 16))
                        .foregroundStyle(iconTint)
                }
            }
            .frame(width: 22, height: 22, alignment: .center)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(SlabFont.mono(size: 13, weight: .medium))
                    .foregroundStyle(AppColor.text)
                Text(detail)
                    .font(SlabFont.sans(size: 12))
                    .foregroundStyle(AppColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .stroke(AppColor.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    /// "{N} lines · X% margin" when the lot has a manual override; "{N}
    /// lines · ladder-priced" when each scan was priced via the per-store
    /// margin ladder. Avoids surfacing a single arbitrary percentage when
    /// the underlying scans were priced at different tiers.
    private var marginSubtitle: String {
        if let pct = lot.marginPctSnapshot {
            return "\(scans.count) lines · \(Int((pct * 100).rounded()))% margin"
        }
        return "\(scans.count) lines · ladder-priced"
    }

    private var canMarkPaid: Bool {
        let state = LotOfferState(rawValue: lot.lotOfferState) ?? .drafting
        return state == .accepted || state == .presented
    }

    private func commit() {
        commitState = Self.runCommit(
            lot: lot,
            repo: offerRepository(),
            paymentMethod: paymentMethod,
            paymentReference: paymentReference.isEmpty ? nil : paymentReference,
            now: Date()
        )
    }

    /// Runs the actual commit through `OfferRepository`, returning the next
    /// `CommitState` to apply. Pulled out as a static so tests can drive the
    /// synchronous-throw path (the original bug — state stranded in
    /// `.committing` while the error sat below) without standing up a SwiftUI
    /// runtime. Returning the state explicitly (rather than setting via a
    /// closure) lets the call site keep its single `commitState = ...`
    /// assignment so a future reader can see the whole transition at a glance.
    static func runCommit(
        lot: Lot,
        repo: OfferRepository,
        paymentMethod: String,
        paymentReference: String?,
        now: Date
    ) -> CommitState {
        do {
            if LotOfferState(rawValue: lot.lotOfferState) != .accepted {
                try repo.recordAcceptance(lot)
            }
            try repo.commit(
                lot: lot,
                paymentMethod: paymentMethod,
                paymentReference: paymentReference
            )
            return .committing(startedAt: now)
        } catch {
            // Synchronous throw — keep the user in control. Reset to a CTA they
            // can press again instead of leaving them stranded mid-"Committing…".
            return .error(error.localizedDescription)
        }
    }

    private var totalBuyCents: Int64 {
        scans.compactMap(\.buyPriceCents).reduce(0, +)
    }

    private func offerRepository() -> OfferRepository {
        OfferRepository(
            context: context, kicker: kicker,
            currentStoreId: lot.storeId,
            currentUserId: session.userId ?? UUID()
        )
    }

    private func formattedCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        return Currency.usdFormatter.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
}
