import SwiftUI

/// Full-screen "tap to resume" gate shown after a bulk-scan session
/// returns from background. The whole scrim is a single `Button` so the
/// user — typically one-handed, under fluorescent shop lighting — can
/// tap anywhere to re-engage OCR. The North Star: keep the user in the
/// loop. Without this gate, foregrounding a pocketed phone could
/// silently spin up the recognizer on a black frame.
///
/// **No gold here.** Per `.impeccable.md`'s "one gold thing per screen"
/// rule, gold stays reserved for live CTAs (the simulator scan button,
/// the live status pill). The gate uses `text` + `muted` + `dim` only —
/// premium, sober, paused.
struct ResumeScanGate: View {
    let onResume: () -> Void

    var body: some View {
        Button(action: onResume) {
            ZStack {
                // Dark, nearly-opaque scrim over the camera. The camera
                // is still running below — only OCR is suspended — but
                // the scrim says "we are paused" loudly enough that a
                // pocketed phone glance reads as "not live".
                AppColor.ink.opacity(0.78)
                    .ignoresSafeArea()

                VStack(spacing: Spacing.l) {
                    Image(systemName: "viewfinder.circle")
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(AppColor.text)
                        .accessibilityHidden(true)
                    KickerLabel("Paused")
                    Text("Scanning paused")
                        .font(SlabFont.serif(size: 28))
                        .tracking(-0.4)
                        .foregroundStyle(AppColor.text)
                    Text("Tap the viewfinder to resume.")
                        .font(SlabFont.sans(size: 14))
                        .foregroundStyle(AppColor.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Spacing.xxxl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // `.contentShape(Rectangle())` so the entire scrim — not
            // just the glyph stack — is the tap target. Hit area >> 44pt.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bulk-scan-resume-gate")
        .accessibilityLabel("Scanning paused. Double tap to resume.")
        .accessibilityHint("Tap anywhere on the screen to resume scanning.")
        .accessibilityAddTraits(.isModal)
    }
}

#Preview("ResumeScanGate") {
    ZStack {
        // Stand-in for the dimmed live camera underneath.
        AppColor.ink
            .overlay(
                Text("(camera below)")
                    .font(SlabFont.sans(size: 12))
                    .foregroundStyle(AppColor.dim)
            )
        ResumeScanGate(onResume: {})
    }
    .ignoresSafeArea()
}
