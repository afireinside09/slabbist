import SwiftUI

/// Bottom-of-the-shell sync status indicator. Bound to OutboxStatus +
/// Reachability via @Environment. Auto-collapses to zero height when
/// state is "Up to date" so it's not permanent chrome.
///
/// When `failedCount > 0` the pill switches to an error tone and a
/// "tap to review" affordance that presents the failures sheet, so
/// `.failed` rows are never silently buried.
struct SyncStatusPill: View {
    @Environment(OutboxStatus.self) private var status
    @Environment(Reachability.self) private var reachability
    /// Closure the host provides to present the failures sheet. The pill
    /// stays decoupled from the actor; the host owns the drainer reference
    /// and wires up the loader / retry / discard handlers.
    var onReviewFailures: () -> Void = {}

    var body: some View {
        // P2.4: keep a single root identity across all states so the
        // pill cross-fades rather than destruction+insertion. We always
        // render the same `Button`; the failure state enables the
        // action, every other state disables it. The pill collapses to
        // 0 height when there's nothing to say (still the same Button —
        // SwiftUI just animates the frame).
        let state = display
        Button(action: onReviewFailures) {
            pillBody(state)
        }
        .buttonStyle(.plain)
        .disabled(state?.role != .failure)
        .accessibilityIdentifier("sync-status-pill")
        .accessibilityLabel(state?.accessibilityLabel ?? "Sync up to date")
        .accessibilityHint(state?.role == .failure ? "Open failed writes" : "")
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    @ViewBuilder
    private func pillBody(_ state: PillDisplay?) -> some View {
        HStack(spacing: Spacing.s) {
            if let state, state.showsSpinner {
                ProgressView()
                    .controlSize(.mini)
                    .tint(state.tone)
            }
            if let state {
                Text(state.label)
                    .font(SlabFont.sans(size: 12, weight: state.role == .failure ? .medium : .regular))
                    .foregroundStyle(state.tone)
            }
        }
        .padding(.horizontal, Spacing.l)
        .frame(maxWidth: .infinity)
        .frame(height: state == nil ? 0 : 24)
        .background(AppColor.surface)
    }

    private var display: PillDisplay? {
        // Failures take priority — never let the pill hide while `.failed`
        // rows are sitting in the local outbox.
        if status.failedCount > 0 {
            let n = status.failedCount
            let writes = n == 1 ? "write" : "writes"
            return PillDisplay(
                label: "\(n) \(writes) failed — tap to review",
                showsSpinner: false,
                tone: AppColor.negative,
                role: .failure,
                accessibilityLabel: "\(n) \(writes) failed. Tap to review."
            )
        }
        if status.isPaused {
            // A5: distinguish the two auth states by the resolved authState
            // first, with a fall-through to lastError copy for legacy callers.
            switch status.authState {
            case .reconnecting:
                return PillDisplay(
                    label: "Reconnecting…",
                    showsSpinner: true,
                    tone: AppColor.dim,
                    role: .info,
                    accessibilityLabel: "Reconnecting to sync"
                )
            case .signedOut:
                return PillDisplay(
                    label: "Sign in to sync",
                    showsSpinner: false,
                    tone: AppColor.negative,
                    role: .warning,
                    accessibilityLabel: "Sign in to sync"
                )
            case nil:
                // No authState resolved yet — fall back to lastError copy.
                let label = status.lastError ?? "Sign in to sync"
                return PillDisplay(
                    label: label,
                    showsSpinner: false,
                    tone: AppColor.dim,
                    role: .info,
                    accessibilityLabel: label
                )
            }
        }
        if status.pendingCount == 0 && !status.isDraining {
            return nil // collapsed — "Up to date"
        }
        if reachability.status == .offline {
            let label = "Offline — \(status.pendingCount) pending"
            return PillDisplay(
                label: label,
                showsSpinner: false,
                tone: AppColor.dim,
                role: .info,
                accessibilityLabel: label
            )
        }
        let label = "Syncing \(status.pendingCount)…"
        return PillDisplay(
            label: label,
            showsSpinner: true,
            tone: AppColor.dim,
            role: .info,
            accessibilityLabel: label
        )
    }

    private struct PillDisplay: Equatable {
        let label: String
        let showsSpinner: Bool
        let tone: Color
        let role: Role
        let accessibilityLabel: String

        enum Role: Equatable { case info, warning, failure }
    }
}

#Preview("Up to date — hidden") {
    SyncStatusPill()
        .environment(OutboxStatus())
        .environment(Reachability())
        .background(AppColor.ink)
}

#Preview("Syncing — 3 pending") {
    let status = OutboxStatus()
    status.update(pendingCount: 3, isDraining: true)
    return SyncStatusPill()
        .environment(status)
        .environment(Reachability())
        .background(AppColor.ink)
}

#Preview("Offline — 5 pending") {
    let status = OutboxStatus()
    status.update(pendingCount: 5, isDraining: false)
    let reach = Reachability()
    reach.applyForTesting(status: .offline)
    return SyncStatusPill()
        .environment(status)
        .environment(reach)
        .background(AppColor.ink)
}

#Preview("Paused — reconnecting") {
    let status = OutboxStatus()
    status.setPaused(true, reason: "Reconnecting…", authState: .reconnecting)
    return SyncStatusPill()
        .environment(status)
        .environment(Reachability())
        .background(AppColor.ink)
}

#Preview("Paused — signed out") {
    let status = OutboxStatus()
    status.setPaused(true, reason: "Sign in to sync", authState: .signedOut)
    return SyncStatusPill()
        .environment(status)
        .environment(Reachability())
        .background(AppColor.ink)
}

#Preview("Failed writes — 2 stuck") {
    let status = OutboxStatus()
    status.update(pendingCount: 0, failedCount: 2, isDraining: false)
    return SyncStatusPill()
        .environment(status)
        .environment(Reachability())
        .background(AppColor.ink)
}
