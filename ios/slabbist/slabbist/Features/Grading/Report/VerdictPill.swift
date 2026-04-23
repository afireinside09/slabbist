import SwiftUI

struct VerdictPill: View {
    let verdict: String
    let confidence: String

    var body: some View {
        HStack(spacing: 8) {
            Text(verdictLabel(verdict))
                .font(.headline)
            Text(confidence.capitalized + " confidence")
                .font(.caption)
                .opacity(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(verdictColor(verdict), in: Capsule())
        .foregroundStyle(.white)
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

    private func verdictColor(_ v: String) -> Color {
        switch v {
        case "submit_express": return .green
        case "submit_value":   return .teal
        case "submit_economy": return .blue
        case "do_not_submit":  return .red
        default:               return .orange
        }
    }
}
