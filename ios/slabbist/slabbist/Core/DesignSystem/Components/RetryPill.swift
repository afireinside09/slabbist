import SwiftUI

/// Compact, negative-tinted pill that signals "this row failed transiently —
/// tap to retry". Designed for trailing alignment in the scan queue row
/// where space is tight (the row also has a leading status dot, a title,
/// and an in-list chevron). Visible frame is ~22pt tall but `minHeight: 44`
/// keeps the HIG-mandated 44pt touch target so taps still register
/// reliably when the user's thumb is on the tail of a row.
///
/// `attempts` controls the copy: 1 → "RETRY"; >=2 → an `arrow.clockwise`
/// glyph plus "RETRY (N)". The pill never disables itself — back-off is the
/// outbox's job, not the UI's, so the user keeps a single recourse.
struct RetryPill: View {
    let attempts: Int
    let accessibilityLabel: String?

    init(attempts: Int = 1, accessibilityLabel: String? = nil) {
        self.attempts = attempts
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if attempts >= 2 {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(labelText)
                .font(SlabFont.mono(size: 11, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
        }
        .foregroundStyle(AppColor.negative)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .stroke(AppColor.negative.opacity(0.55), lineWidth: 1)
        )
        // Visible frame is ~22pt tall; minHeight pushes the hit target
        // out to HIG's 44pt without growing the visible pill.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel ?? labelText)
    }

    private var labelText: String {
        attempts >= 2 ? "Retry (\(attempts))" : "Retry"
    }
}

#Preview("RetryPill") {
    VStack(spacing: Spacing.m) {
        RetryPill()
        RetryPill(attempts: 2)
        RetryPill(attempts: 3)
    }
    .padding()
    .background(AppColor.ink)
}
