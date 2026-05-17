import SwiftUI

struct ScanQueueView: View {
    let scans: [Scan]
    /// Callback fired when the user taps the retry pill on a transiently-failed
    /// row. Optional so previews / tests can pass `nil` and the pill becomes
    /// a no-op; production wiring lives in `BulkScanView`, which forwards to
    /// `BulkScanViewModel.retryValidation(scan:)`.
    let onRetry: ((Scan) -> Void)?
    /// Callback fired when the user taps a stale `.fetching` row's Retry
    /// pill. Forwards to `CompFetchService.fetch` via the host (`BulkScanView`)
    /// so the retry shares the same in-flight de-dup keyset the auto-fetch
    /// path uses. Optional so previews / tests can no-op.
    let onRetryCompFetch: ((Scan) -> Void)?
    /// Callback fired when the user taps the inline "Set price" / edit pill.
    /// The host presents `ManualPriceSheet`; this view owns no sheet of its
    /// own because it's nested inside the bulk-scan camera surface.
    let onPresentManualPrice: ((Scan) -> Void)?

    /// Window after a transient failure during which the row keeps reading
    /// "validating…" instead of flipping to the retry pill. Smooths out fast
    /// network errors so the user doesn't see a retry pill appear and vanish.
    private static let transientGracePeriod: TimeInterval = 10

    /// Max height for the queue panel. Sized to ~2 compact rows so the
    /// camera area keeps the majority of the screen — older entries stay
    /// reachable through the inner ScrollView without pushing the live UI
    /// off screen.
    private static let maxPanelHeight: CGFloat = 116

    init(
        scans: [Scan],
        onRetry: ((Scan) -> Void)? = nil,
        onRetryCompFetch: ((Scan) -> Void)? = nil,
        onPresentManualPrice: ((Scan) -> Void)? = nil
    ) {
        self.scans = scans
        self.onRetry = onRetry
        self.onRetryCompFetch = onRetryCompFetch
        self.onPresentManualPrice = onPresentManualPrice
    }

    var body: some View {
        if scans.isEmpty {
            Text("No scans yet")
                .font(SlabFont.sans(size: 13))
                .foregroundStyle(AppColor.dim)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.md)
        } else {
            // Trim to a reasonable backlog so the in-camera queue doesn't
            // hold every scan from the session — the lot detail screen is
            // the canonical record. 12 rows is enough headroom that a
            // user scanning quickly still sees recent context but the
            // ScrollView has a small, snappy content size.
            let visible = Array(scans.prefix(12))
            SlabCard {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(visible, id: \.id) { scan in
                            if scan.id != visible.first?.id {
                                SlabCardDivider()
                            }
                            row(for: scan)
                        }
                    }
                }
                .frame(maxHeight: Self.maxPanelHeight)
            }
        }
    }

    /// Each row is split into two adjacent tap regions:
    ///   - The leading title area is a `NavigationLink`-backed button that
    ///     drills into `ScanDetailView`.
    ///   - The trailing area is one of: cert-lookup retry pill (C1),
    ///     stale comp-fetch retry pill (C2), `SetPricePill` for `needsPrice`
    ///     / `hasManual` (F3), the reconciled dollar amount, or the mono
    ///     status trail (decorative).
    ///
    /// Splitting them avoids the `.simultaneousGesture` fragility called out
    /// in the C1 spec — SwiftUI gracefully routes the tap to whichever
    /// button the touch lands on.
    private func row(for scan: Scan) -> some View {
        HStack(spacing: Spacing.m) {
            NavigationLink(value: scan) {
                HStack(spacing: Spacing.m) {
                    Circle()
                        .fill(statusColor(for: scan))
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(statusAccessibilityLabel(for: scan))
                    // On compact widths (iPhone SE) or AX Dynamic Type
                    // the joined "GRADER · CERT" string truncates the
                    // cert digits — the one piece of information the
                    // row actually exists to surface. `ViewThatFits`
                    // keeps the single-line layout when it fits and
                    // drops to a two-line stack with the cert on its
                    // own line when it doesn't.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.xs) {
                            Text(scan.grader.rawValue)
                                .slabRowTitle()
                                .lineLimit(1)
                            Text("·")
                                .slabRowTitle()
                                .foregroundStyle(AppColor.dim)
                            Text(scan.certNumber)
                                .slabRowTitle()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(scan.grader.rawValue)
                                .slabRowTitle()
                                .lineLimit(1)
                            Text(scan.certNumber)
                                .slabRowTitle()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            trailing(for: scan)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }

    /// Accessibility narration for the colored status dot. Mirrors the
    /// same branching `statusColor(for:)` uses so screen-reader users
    /// get the state a sighted user reads from the dot's color.
    private func statusAccessibilityLabel(for scan: Scan) -> String {
        if isTransientFailed(scan) { return "Status: failed, retry available" }
        switch scan.status {
        case .validated:         return "Status: validated"
        case .pendingValidation: return "Status: pending validation"
        case .validationFailed:  return "Status: failed"
        case .manualEntry:       return "Status: manual entry"
        }
    }

    /// Trailing-edge content for a queue row. Cert-lookup retry takes
    /// priority because a row that hasn't validated yet has no meaningful
    /// comp/manual state; everything below depends on a validated scan.
    @ViewBuilder
    private func trailing(for scan: Scan) -> some View {
        if isTransientFailed(scan) {
            Button {
                onRetry?(scan)
            } label: {
                RetryPill(attempts: max(scan.validationAttemptCount, 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry cert lookup for \(scan.grader.rawValue) \(scan.certNumber)")
            .accessibilityHint("Tries the cert lookup again")
            .accessibilityIdentifier("scan-retry-\(scan.certNumber)")
        } else {
            // The queue view doesn't carry the snapshot @Query (the
            // panel is nested inside the bulk-scan camera surface where
            // the @Query overhead would burn cycles on every frame).
            // Passing `nil` falls through to `.fetching`/`.idle` for
            // pure legacy-snapshot rows — fine here because such rows
            // surface on the lot-detail screen with the full state.
            switch ScanRowTrailingState.resolve(for: scan) {
            case .needsPrice:
                SetPricePill(priceCents: nil) { onPresentManualPrice?(scan) }
                    .accessibilityLabel("Set manual price for \(scan.grader.rawValue) \(scan.certNumber)")
                    .accessibilityHint("Opens the price entry sheet")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("set-price-pill-\(scan.certNumber)")
            case .hasManual(let cents):
                SetPricePill(priceCents: cents) { onPresentManualPrice?(scan) }
                    .accessibilityLabel("Manual price \(SetPricePill.formattedCompact(cents)). Tap to edit.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("edit-price-pill-\(scan.certNumber)")
            case .hasManualWithReconciled(let manualCents, _):
                // Manual price entered, then a comp landed. Keep the
                // pencil pill so the user's input stays visible (P1.3
                // — the lot total uses the reconciled value via
                // `aggregateCents`; the row reflects what the operator
                // typed).
                SetPricePill(priceCents: manualCents) { onPresentManualPrice?(scan) }
                    .accessibilityLabel("Manual price \(SetPricePill.formattedCompact(manualCents)). Tap to edit.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("edit-price-pill-\(scan.certNumber)")
            case .hasReconciled(let cents), .hasSnapshot(let cents):
                Text(SetPricePill.formattedCompact(cents))
                    .font(SlabFont.mono(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.text)
                    .lineLimit(1)
            case .staleFetching:
                // The comp fetch task is gone (likely an app kill); surface
                // the same negative-tinted Retry pill the cert-lookup
                // failures use so the recovery affordance is visually
                // identical across both stuck-state classes.
                Button {
                    onRetryCompFetch?(scan)
                } label: {
                    RetryPill()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry comp fetch for \(scan.grader.rawValue) \(scan.certNumber)")
                .accessibilityHint("Tries the comp fetch again")
                .accessibilityIdentifier("comp-retry-\(scan.certNumber)")
            case .fetching, .failed, .idle:
                Text(scan.status.rawValue.replacingOccurrences(of: "_", with: " "))
                    .font(SlabFont.mono(size: 11))
                    .foregroundStyle(AppColor.dim)
                    .lineLimit(1)
            }
        }
    }

    /// True when the scan should surface a retry pill instead of the mono
    /// status trail. Requires:
    ///   1. Still `.pendingValidation` (we don't replace the "validating…"
    ///      pill with retry while a lookup is genuinely in flight).
    ///   2. A persisted `"transient"` failure reason.
    ///   3. At least `transientGracePeriod` seconds since the last attempt
    ///      so the row doesn't flicker pill ↔ mono trail when a lookup
    ///      fails quickly and the next attempt is about to fire.
    ///
    /// Note: the 10s gate is wall-clock — the row only flips from
    /// "validating…" to the retry pill the next time `recentScans`
    /// refreshes (i.e. the next SwiftData write or `refreshRecent()` call).
    /// In practice the failure write itself triggers a refresh, so the
    /// pill appears within one runloop tick of the 10s window opening.
    private func isTransientFailed(_ scan: Scan) -> Bool {
        guard scan.status == .pendingValidation else { return false }
        guard scan.validationFailureReason == "transient" else { return false }
        guard let last = scan.validationLastAttemptAt else { return false }
        return Date().timeIntervalSince(last) >= Self.transientGracePeriod
    }

    private func statusColor(for scan: Scan) -> Color {
        if isTransientFailed(scan) { return AppColor.negative }
        switch scan.status {
        case .validated:          return AppColor.positive
        case .pendingValidation:  return AppColor.gold
        case .validationFailed:   return AppColor.negative
        case .manualEntry:        return AppColor.muted
        }
    }
}
