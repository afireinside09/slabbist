import SwiftUI

struct ScanQueueView: View {
    let scans: [Scan]

    /// Max height for the queue panel. Sized to ~3 rows so the panel never
    /// grows tall enough to cover the centered `CapturedReviewCard` modal
    /// during a bulk-scan session — older entries stay reachable through
    /// the inner ScrollView without pushing the live UI off screen.
    private static let maxPanelHeight: CGFloat = 192

    var body: some View {
        if scans.isEmpty {
            Text("No scans yet")
                .font(SlabFont.sans(size: 13))
                .foregroundStyle(AppColor.dim)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.md)
        } else {
            // Trim to a reasonable backlog so the in-camera queue doesn't
            // hold every scan from the session — the lot detail screen is
            // the canonical record. 12 rows is enough headroom that a
            // user scanning quickly still sees recent context but the
            // ScrollView has a small, snappy content size.
            let visible = Array(scans.prefix(12))
            SlabCard {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(visible, id: \.id) { scan in
                            if scan.id != visible.first?.id {
                                SlabCardDivider()
                            }
                            NavigationLink(value: scan) {
                                row(for: scan)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: Self.maxPanelHeight)
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
