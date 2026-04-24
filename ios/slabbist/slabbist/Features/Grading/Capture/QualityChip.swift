import SwiftUI

struct QualityChip: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
                .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
                .accessibilityLabel("Capture quality: \(message)")
        }
    }
}
