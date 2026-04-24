import SwiftUI

struct FirstRunConsentView: View {
    let onAgree: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Pre-grade Estimator")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(consentBody)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
            PrimaryGoldButton(title: "I understand — continue") {
                onAgree()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .padding()
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
