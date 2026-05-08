import SwiftUI

/// Bottom-of-the-shell sync status indicator. Bound to OutboxStatus +
/// Reachability via @Environment. Auto-collapses to zero height when
/// state is "Up to date" so it's not permanent chrome.
struct SyncStatusPill: View {
    @Environment(OutboxStatus.self) private var status
    @Environment(Reachability.self) private var reachability

    var body: some View {
        HStack(spacing: Spacing.s) {
            if let state = display {
                if state.showsSpinner {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(AppColor.dim)
                }
                Text(state.label)
                    .font(SlabFont.sans(size: 12))
                    .foregroundStyle(AppColor.dim)
            }
        }
        .padding(.horizontal, Spacing.l)
        .frame(maxWidth: .infinity)
        .frame(height: display == nil ? 0 : 24)
        .background(AppColor.surface)
        .accessibilityIdentifier("sync-status-pill")
        .accessibilityLabel(display?.label ?? "Sync up to date")
        .animation(.easeInOut(duration: 0.2), value: display?.label)
    }

    private var display: PillDisplay? {
        if status.isPaused {
            return PillDisplay(label: "Sign in to sync", showsSpinner: false)
        }
        if status.pendingCount == 0 && !status.isDraining {
            return nil // collapsed — "Up to date"
        }
        if reachability.status == .offline {
            return PillDisplay(label: "Offline — \(status.pendingCount) pending", showsSpinner: false)
        }
        return PillDisplay(label: "Syncing \(status.pendingCount)…", showsSpinner: true)
    }

    private struct PillDisplay: Equatable {
        let label: String
        let showsSpinner: Bool
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

#Preview("Paused — auth") {
    let status = OutboxStatus()
    status.setPaused(true, reason: "Sign in to sync")
    return SyncStatusPill()
        .environment(status)
        .environment(Reachability())
        .background(AppColor.ink)
}
