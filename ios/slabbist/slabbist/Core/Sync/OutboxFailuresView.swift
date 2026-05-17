import SwiftUI
import SwiftData

/// Failures review sheet (A2). Presented when the user taps the
/// `SyncStatusPill` while `failedCount > 0`. Lists every `.failed`
/// outbox row with two affordances:
///
/// * Retry — flips the row back to `.pending` with `attempts = 0` and
///   `nextAttemptAt = .now`, then kicks the drainer.
/// * Discard — permanently deletes the row from the local outbox. The
///   server-side state may or may not have landed; the user is the
///   authority for "I'm done with this write attempt."
///
/// Visual language follows `.impeccable.md`: dark `ink` background,
/// hairline separators, Instrument Serif title, `.monospaced` ages.
/// No drop shadows, no nested cards. `neg` tone on the error message.
struct OutboxFailuresView: View {
    /// Loaded once on appear, refreshed after each action so the user
    /// sees the row vanish immediately. Snapshot type so we don't hold
    /// `OutboxItem` references across the actor boundary.
    @State private var rows: [OutboxDrainer.FailedRowSnapshot] = []
    @State private var isLoading: Bool = true
    private let loader: @Sendable () async -> [OutboxDrainer.FailedRowSnapshot]
    private let onRetry: @Sendable (UUID) async -> Void
    private let onDiscard: @Sendable (UUID) async -> Void
    private let onClose: () -> Void

    init(
        loader: @escaping @Sendable () async -> [OutboxDrainer.FailedRowSnapshot],
        onRetry: @escaping @Sendable (UUID) async -> Void,
        onDiscard: @escaping @Sendable (UUID) async -> Void,
        onClose: @escaping () -> Void
    ) {
        self.loader = loader
        self.onRetry = onRetry
        self.onDiscard = onDiscard
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            SlabbedRoot {
                content
            }
            .navigationTitle("")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onClose() }
                        .font(SlabFont.sans(size: 14, weight: .medium))
                        .foregroundStyle(AppColor.text)
                }
            }
        }
        .task {
            rows = await loader()
            isLoading = false
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            header
            if isLoading {
                Spacer()
                ProgressView().tint(AppColor.dim)
                Spacer()
            } else if rows.isEmpty {
                Spacer()
                Text("No failed writes — everything caught up.")
                    .font(SlabFont.sans(size: 14))
                    .foregroundStyle(AppColor.muted)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            FailureRowView(
                                row: row,
                                onRetry: { Task { await retry(row.id) } },
                                onDiscard: { Task { await discard(row.id) } }
                            )
                            Rectangle()
                                .fill(AppColor.hairline)
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.l)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Sync")
            Text("Failed writes")
                .slabTitle()
            Text("These changes never reached the server. Retry to try again, or discard to drop them locally.")
                .font(SlabFont.sans(size: 14))
                .foregroundStyle(AppColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func retry(_ id: UUID) async {
        await onRetry(id)
        rows = await loader()
    }

    private func discard(_ id: UUID) async {
        await onDiscard(id)
        rows = await loader()
    }
}

private struct FailureRowView: View {
    let row: OutboxDrainer.FailedRowSnapshot
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(humanKind(row.kind))
                    .slabRowTitle()
                Spacer()
                // P2.5: `Text(_:style:.relative)` auto-refreshes the
                // formatted age — a user staring at the sheet for 90s
                // sees the label tick from "1 minute ago" to "2 minutes
                // ago" without manual timer plumbing. VoiceOver picks up
                // the same string.
                Text(row.createdAt, style: .relative)
                    .font(SlabFont.mono(size: 12))
                    .foregroundStyle(AppColor.dim)
            }
            if let err = row.lastError, !err.isEmpty {
                Text(truncated(err))
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Spacing.m) {
                // P2.9: hairline-bordered secondary buttons matching the
                // design system. No system-material chrome, no gold —
                // gold is reserved for the pill itself (one-gold-per-screen).
                Button("Retry", action: onRetry)
                    .buttonStyle(FailureRowButtonStyle(role: .standard))
                    .accessibilityHint("Try this write again now")
                Button("Discard", action: onDiscard)
                    .buttonStyle(FailureRowButtonStyle(role: .destructive))
                    .accessibilityHint("Permanently drop this write")
            }
        }
        .padding(.vertical, Spacing.m)
        // P2.9: `.contain` keeps the individual Retry/Discard buttons as
        // focusable VoiceOver elements (`.combine` would flatten them
        // into a single non-interactive blob).
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(humanKind(row.kind)) — failed write")
    }

    private func truncated(_ text: String) -> String {
        let max = 280
        if text.count <= max { return text }
        return String(text.prefix(max)) + "…"
    }

    /// Map the kind to friendlier copy. Buy-side IA — these strings appear
    /// to a vendor staring at a stuck queue, not a developer.
    private func humanKind(_ kind: OutboxKind) -> String {
        switch kind {
        case .insertScan, .updateScan: return "Scan"
        case .updateScanOffer:         return "Scan offer"
        case .updateScanBuyPrice:      return "Scan buy price"
        case .deleteScan:              return "Scan removal"
        case .insertLot, .updateLot:   return "Lot"
        case .updateLotOffer:          return "Lot offer"
        case .recomputeLotOffer:       return "Lot offer recalc"
        case .deleteLot:               return "Lot removal"
        case .upsertVendor:            return "Vendor"
        case .archiveVendor:           return "Vendor archive"
        case .certLookupJob:           return "Cert lookup"
        case .priceCompJob:            return "Price comp"
        case .commitTransaction:       return "Transaction commit"
        case .voidTransaction:         return "Transaction void"
        case .updateStoreMargin:       return "Margin settings"
        }
    }
}

/// Hairline-bordered button style for the failures-sheet row affordances.
/// Mirrors `SecondaryButtonStyle` (existing `Core/DesignSystem/Components/
/// SecondaryButton.swift`) but sized for inline-row use rather than full
/// width. Keeps the dark+gold language: no system chrome, no shadows.
private struct FailureRowButtonStyle: ButtonStyle {
    enum Role { case standard, destructive }
    var role: Role

    func makeBody(configuration: Configuration) -> some View {
        let tone: Color = role == .destructive ? AppColor.negative : AppColor.muted
        configuration.label
            .font(SlabFont.sans(size: 13, weight: .medium))
            .foregroundStyle(tone)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .stroke(tone.opacity(0.6), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

#Preview("Failures sheet — populated") {
    OutboxFailuresView(
        loader: {
            [
                .init(
                    id: UUID(),
                    kind: .updateScanOffer,
                    lastError: "Forbidden by RLS: scan does not belong to this store",
                    attempts: 2,
                    createdAt: Date().addingTimeInterval(-180)
                ),
                .init(
                    id: UUID(),
                    kind: .insertLot,
                    lastError: "Constraint violation: store_id null",
                    attempts: 1,
                    createdAt: Date().addingTimeInterval(-3600)
                )
            ]
        },
        onRetry: { _ in },
        onDiscard: { _ in },
        onClose: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Failures sheet — empty") {
    OutboxFailuresView(
        loader: { [] },
        onRetry: { _ in },
        onDiscard: { _ in },
        onClose: {}
    )
    .preferredColorScheme(.dark)
}
