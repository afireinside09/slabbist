import SwiftUI

/// Floating in-camera review card shown after the recognizer locks onto a
/// stable cert. Pauses the OCR pipeline so the user can confirm or correct
/// the inferred grader before the scan commits — necessary because Vision
/// frequently misreads the "PSA" keyword as "PEA" / "FA" and the recognizer
/// has to infer grader from digit length.
struct CapturedReviewCard: View {
    @State private var grader: Grader
    let initialCertNumber: String
    let onConfirm: (CertCandidate) -> Void
    let onCancel: () -> Void

    init(
        candidate: CertCandidate,
        onConfirm: @escaping (CertCandidate) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._grader = State(initialValue: candidate.grader)
        self.initialCertNumber = candidate.certNumber
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            header

            VStack(alignment: .leading, spacing: Spacing.s) {
                KickerLabel("Cert number")
                Text(initialCertNumber)
                    .font(SlabFont.mono(size: 22, weight: .bold))
                    .foregroundStyle(AppColor.text)
                    .accessibilityIdentifier("review-cert-number")
            }

            VStack(alignment: .leading, spacing: Spacing.s) {
                KickerLabel("Grader (tap to correct)")
                Picker("Grader", selection: $grader) {
                    ForEach(Grader.allCases, id: \.self) { g in
                        Text(g.rawValue).tag(g)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: Spacing.m) {
                Button(action: { onCancel() }) {
                    Text("Discard")
                        .font(SlabFont.sans(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColor.dim, lineWidth: 1)
                        )
                        .foregroundStyle(AppColor.muted)
                }
                .buttonStyle(.plain)

                PrimaryGoldButton(
                    title: "Confirm",
                    isEnabled: true
                ) {
                    onConfirm(currentCandidate)
                }
            }
        }
        .padding(Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AppColor.ink.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(AppColor.gold.opacity(0.45), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
    }

    private var currentCandidate: CertCandidate {
        CertCandidate(
            grader: grader,
            certNumber: initialCertNumber,
            confidence: 1.0,
            rawText: "review-confirmed"
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                KickerLabel("Detected")
                Text("Confirm slab").slabRowTitle()
            }
            Spacer()
            Image(systemName: "viewfinder.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(AppColor.gold)
        }
    }
}
