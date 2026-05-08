import SwiftUI

struct VerdictPill: View {
    let verdict: String
    let confidence: String

    var body: some View {
        HStack(spacing: Spacing.s) {
            Circle()
                .fill(verdictTint)
                .frame(width: 8, height: 8)
            Text(verdictLabel(verdict))
                .font(SlabFont.sans(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.text)
            Text(confidence.uppercased() + " CONFIDENCE")
                .font(SlabFont.sans(size: 10, weight: .medium))
                .tracking(1.6)
                .foregroundStyle(AppColor.dim)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(
            Capsule().fill(AppColor.elev)
        )
        .overlay(
            Capsule().stroke(AppColor.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(verdictLabel(verdict)), \(confidence) confidence")
    }

    private func verdictLabel(_ v: String) -> String {
        switch v {
        case "submit_express":     return "Submit — Express tier"
        case "submit_value":       return "Submit — Value tier"
        case "submit_economy":     return "Submit — Economy tier"
        case "do_not_submit":      return "Do not submit"
        case "borderline_reshoot": return "Borderline — reshoot"
        default:                   return v
        }
    }

    private var verdictTint: Color {
        switch verdict {
        case "submit_express", "submit_value", "submit_economy":
            return AppColor.positive
        case "do_not_submit":
            return AppColor.negative
        case "borderline_reshoot":
            return AppColor.gold
        default:
            return AppColor.muted
        }
    }
}
