import SwiftUI

/// Modal scrim + status card layered above the live camera in
/// `GradingCaptureView`. Renders nothing during the `.front`/`.back`
/// capture phases (so the user shoots photos normally) and slides in for
/// `.uploading` / `.analyzing` / `.failed`, where the in-progress or
/// failed network call would otherwise be invisible.
///
/// North-star: the user always knows the app is doing something with
/// their photos. The camera stays mounted under the scrim — the photos
/// they just took are still safe, and the "Try again" CTA on failure
/// re-uses them rather than asking for a re-shoot.
struct AnalysisOverlay: View {
    let phase: GradingCaptureViewModel.Phase
    /// Concrete error surfaced from the last `runAnalysis` throw. When
    /// non-nil and the phase is `.failed`, used to special-case offline
    /// copy. Optional because the view model's `.failed(message:)` may
    /// arrive without the originating `Error` reference (e.g. the
    /// "Missing capture data" pre-condition path).
    let error: Error?
    let onRetry: () -> Void
    let onCancel: () -> Void

    /// Focuses VoiceOver on the status card's title when the overlay
    /// appears. Snapping focus here is what makes the overlay feel
    /// modal under VoiceOver — without it, focus stays on whatever
    /// camera-side control the user just tapped. (P2.9)
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        switch phase {
        case .front, .back, .done:
            EmptyView()
        case .uploading, .analyzing, .failed:
            ZStack {
                // Hairlines, not blur — the design language is opaque
                // scrim over the dimmed camera, not glassmorphism.
                AppColor.ink.opacity(0.86)
                    .ignoresSafeArea()

                statusCard
                    .padding(.horizontal, Spacing.xxl)
            }
            // .isModal at the root so VoiceOver doesn't drift under
            // the scrim. The camera content underneath is also
            // .accessibilityHidden by the host view while the overlay
            // is up — both belt-and-braces hardening. (P2.9)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .transition(.opacity)
            .onAppear { titleFocused = true }
            .onChange(of: phase) { _, _ in
                // Phase transitions inside the overlay (uploading →
                // analyzing, analyzing → failed) re-snap focus so
                // VoiceOver re-announces the new state.
                titleFocused = true
            }
        }
    }

    // MARK: - Card

    private var statusCard: some View {
        SlabCard {
            VStack(spacing: Spacing.l) {
                KickerLabel(kicker)
                    .accessibilityHidden(true)

                glyph

                Text(title)
                    .font(SlabFont.serif(size: 24))
                    .tracking(-0.4)
                    .foregroundStyle(AppColor.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($titleFocused)

                Text(detail)
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.s)

                if case .failed = phase {
                    photosSavedRow
                    PrimaryGoldButton(title: "Try again", action: onRetry)
                    SecondaryButton(title: "Cancel", action: onCancel)
                }
            }
            .padding(Spacing.xxl)
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch phase {
        case .uploading, .analyzing:
            ProgressView()
                .tint(AppColor.gold)
                .controlSize(.large)
                .accessibilityLabel(phase == .uploading ? "Uploading" : "Analyzing")
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .font(SlabFont.sans(size: 32, weight: .regular))
                .foregroundStyle(AppColor.negative)
                .accessibilityHidden(true)
        default:
            EmptyView()
        }
    }

    /// Hairline-outlined reassurance strip — explains the relationship
    /// between the cached UIImages and the "Try again" CTA. Without this
    /// the button is ambiguous (re-shoot? re-network?).
    private var photosSavedRow: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "photo.stack.fill")
                .font(SlabFont.sans(size: 16, weight: .regular))
                .foregroundStyle(AppColor.positive)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Your photos are saved")
                    .font(SlabFont.sans(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.text)
                Text("Tap Try again — we'll skip re-shooting.")
                    .font(SlabFont.sans(size: 11))
                    .foregroundStyle(AppColor.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                .stroke(AppColor.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Copy

    private var kicker: String {
        switch phase {
        case .uploading: return "UPLOADING"
        case .analyzing: return "ANALYZING"
        case .failed:    return "ANALYSIS FAILED"
        default:         return ""
        }
    }

    private var title: String {
        switch phase {
        case .uploading: return "Uploading your photos…"
        case .analyzing: return "Reading the card…"
        case .failed:    return "We couldn't analyze the card."
        default:         return ""
        }
    }

    /// Detail copy. On `.failed`, classifies the underlying `URLError`
    /// so an offline user gets a network-specific message instead of a
    /// generic "Server returned …" string.
    var detail: String {
        switch phase {
        case .uploading:
            return "Don't switch apps — we're sending the front and back to Slabbist for analysis."
        case .analyzing:
            return "This usually takes 8 to 12 seconds. We're looking at centering, corners, and surface."
        case .failed(let message):
            return Self.failureDetail(message: message, error: error)
        default:
            return ""
        }
    }

    /// Visible for testing — chooses the offline string when the
    /// underlying error is a `URLError` in the offline-ish family, else
    /// passes the view-model message through.
    static func failureDetail(message: String, error: Error?) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .timedOut:
                return "You're offline. We'll keep your photos. Reconnect and tap Try again."
            default:
                break
            }
        }
        return message
    }
}

#Preview("AnalysisOverlay — uploading") {
    AnalysisOverlay(
        phase: .uploading,
        error: nil,
        onRetry: {},
        onCancel: {}
    )
    .background(AppColor.ink)
}

#Preview("AnalysisOverlay — analyzing") {
    AnalysisOverlay(
        phase: .analyzing,
        error: nil,
        onRetry: {},
        onCancel: {}
    )
    .background(AppColor.ink)
}

#Preview("AnalysisOverlay — failed") {
    AnalysisOverlay(
        phase: .failed(message: "Server returned 503."),
        error: nil,
        onRetry: {},
        onCancel: {}
    )
    .background(AppColor.ink)
}

#Preview("AnalysisOverlay — failed offline") {
    AnalysisOverlay(
        phase: .failed(message: "Upload failed — try again."),
        error: URLError(.notConnectedToInternet),
        onRetry: {},
        onCancel: {}
    )
    .background(AppColor.ink)
}
