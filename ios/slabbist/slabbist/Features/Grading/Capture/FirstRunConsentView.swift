import SwiftUI

struct FirstRunConsentView: View {
    let onAgree: () -> Void

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                Spacer(minLength: Spacing.xxl)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    KickerLabel("Before you proceed")
                    Text("Pre-grade Estimator").slabTitle()
                }
                Text(consentBody)
                    .font(SlabFont.sans(size: 15))
                    .foregroundStyle(AppColor.muted)
                    .lineSpacing(2)
                Spacer()
                PrimaryGoldButton(title: "I understand — continue") {
                    onAgree()
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.bottom, Spacing.xl)
        }
    }

    private var consentBody: String {
        """
        This is an estimate, not a guarantee. The model can be wrong, especially on subtle surface defects \
        and corner wear that a photo can't reveal. Real grades depend on submission tier, current grader \
        trends, and inspection details we cannot see.

        Slabbist is not responsible for grading outcomes. Use this as a directional check before paying \
        for grading — not as a final answer.
        """
    }
}
