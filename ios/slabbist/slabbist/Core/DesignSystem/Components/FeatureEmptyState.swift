import SwiftUI

/// Empty-state card for the bottom-of-funnel tabs (Lots, Scan,
/// Grade) when the feature has nothing to show yet. Explains *what*
/// the tab does and *how* to use it in 2-3 short steps so the user
/// can self-serve without leaving the screen.
///
/// Compact by design — the steps live inside the same SlabCard as
/// the headline, no separate bullets section, no marketing copy.
struct FeatureEmptyState: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let steps: [String]

    var body: some View {
        SlabCard {
            VStack(spacing: Spacing.l) {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(AppColor.gold.opacity(0.85))
                    .padding(.top, Spacing.l)
                    .accessibilityHidden(true)

                VStack(spacing: Spacing.s) {
                    Text(title)
                        .font(SlabFont.serif(size: 24))
                        .tracking(-0.6)
                        .foregroundStyle(AppColor.text)
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.l)
                }

                if !steps.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: Spacing.s) {
                                Text("\(index + 1)")
                                    .font(SlabFont.mono(size: 11, weight: .semibold))
                                    .foregroundStyle(AppColor.gold)
                                    .frame(width: 16, alignment: .leading)
                                    .accessibilityHidden(true)
                                Text(step)
                                    .font(SlabFont.sans(size: 13))
                                    .foregroundStyle(AppColor.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if steps.isEmpty {
                    Spacer(minLength: Spacing.l)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("FeatureEmptyState") {
    VStack(spacing: Spacing.l) {
        FeatureEmptyState(
            systemImage: "square.stack.3d.up",
            title: "No lots yet",
            subtitle: "A lot is a stack of cards you're processing together — a 500-count, a tournament pickup, a buylist haul.",
            steps: [
                "Tap New bulk scan to create one.",
                "Photograph each slab's label; cards match automatically.",
                "Open a lot anytime to see comps, totals, and what's left.",
            ]
        )
    }
    .padding()
    .background(AppColor.ink)
}
