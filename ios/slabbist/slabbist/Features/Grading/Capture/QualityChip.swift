import SwiftUI

struct QualityChip: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(SlabFont.sans(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.text)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .background(
                    Capsule().fill(AppColor.elev.opacity(0.92))
                )
                .overlay(
                    Capsule().stroke(AppColor.hairlineStrong, lineWidth: 1)
                )
                .accessibilityLabel("Capture quality: \(message)")
        }
    }
}
