import SwiftUI
import UIKit

/// Surfaced on `AuthView` when the user landed there for a reason that isn't
/// their own sign-out (token refresh failure, server-side revocation, etc).
///
/// Design constraints (`.impeccable.md`): no gold — gold belongs to the
/// Sign in CTA. The banner uses `AppColor.negative` for the icon + stroke
/// but keeps the headline/detail at `AppColor.text` / `AppColor.muted` so it
/// reads as informational, not alarming.
///
/// Auto-clears on successful submit — there is no manual dismiss, matching
/// the spec's reasoning that a buy-side user returning to the screen should
/// not have to do extra work to read why they're being asked to sign in.
struct SessionExpiryBanner: View {
    let reason: SessionStore.SignOutReason
    /// AuthView re-mounts on `toggleMode()`, pending-confirmation flips, and
    /// parent VStack rebuilds. Without this guard VoiceOver would re-hear
    /// "Your session ended" on every re-render. Per-banner-lifetime is the
    /// right scope: if the user signs in successfully the banner unmounts
    /// and a future expiry re-announces correctly.
    @State private var didAnnounce: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: "lock.rotation")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColor.negative)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(headline)
                    .font(SlabFont.sans(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.text)
                Text(detail)
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .fill(AppColor.negative.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                        .stroke(AppColor.negative.opacity(0.45), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session-expiry-banner")
        .accessibilityAddTraits(.isStaticText)
        .onAppear {
            guard !didAnnounce else { return }
            didAnnounce = true
            UIAccessibility.post(notification: .announcement, argument: headline)
        }
    }

    var headline: String {
        switch reason {
        case .sessionExpired:     return "Your session ended."
        case .tokenRefreshFailed: return "We couldn't refresh your sign-in."
        case .userInitiated, .launchedFresh: return ""
        }
    }

    var detail: String {
        switch reason {
        case .sessionExpired:
            return "Sign in to keep scanning. Your scans and offers are still saved on this device."
        case .tokenRefreshFailed:
            return "Sign in again — your local data is safe. This usually means a network blip."
        case .userInitiated, .launchedFresh:
            return ""
        }
    }

    /// True when the reason warrants showing the banner. Hoisted as a static
    /// so `AuthView` can ask without re-rendering a hidden view.
    static func shouldShow(for reason: SessionStore.SignOutReason) -> Bool {
        switch reason {
        case .sessionExpired, .tokenRefreshFailed: return true
        case .userInitiated, .launchedFresh: return false
        }
    }
}

#Preview("SessionExpiryBanner — sessionExpired") {
    VStack(spacing: Spacing.l) {
        SessionExpiryBanner(reason: .sessionExpired)
        SessionExpiryBanner(reason: .tokenRefreshFailed)
    }
    .padding()
    .background(AppColor.ink)
}
