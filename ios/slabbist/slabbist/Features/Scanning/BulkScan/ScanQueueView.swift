import SwiftUI

struct ScanQueueView: View {
    let scans: [Scan]

    var body: some View {
        if scans.isEmpty {
            Text("No scans yet")
                .font(SlabFont.sans(size: 13))
                .foregroundStyle(AppColor.dim)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.md)
        } else {
            let visible = Array(scans.prefix(6))
            SlabCard {
                VStack(spacing: 0) {
                    ForEach(visible, id: \.id) { scan in
                        if scan.id != visible.first?.id {
                            SlabCardDivider()
                        }
                        row(for: scan)
                    }
                }
            }
        }
    }

    private func row(for scan: Scan) -> some View {
        HStack(spacing: Spacing.m) {
            Circle()
                .fill(statusColor(for: scan))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(scan.grader.rawValue) · \(scan.certNumber)")
                    .slabRowTitle()
                Text(scan.status.rawValue.replacingOccurrences(of: "_", with: " "))
                    .font(SlabFont.mono(size: 11))
                    .foregroundStyle(AppColor.dim)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }

    private func statusColor(for scan: Scan) -> Color {
        switch scan.status {
        case .validated:          return AppColor.positive
        case .pendingValidation:  return AppColor.gold
        case .validationFailed:   return AppColor.negative
        case .manualEntry:        return AppColor.muted
        }
    }
}
