import SwiftUI

struct ScanQueueView: View {
    let scans: [Scan]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(scans) { scan in
                    scanChip(for: scan)
                }
            }
            .padding(.horizontal, Spacing.m)
        }
        .frame(height: 88)
    }

    private func scanChip(for scan: Scan) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(scan.grader.rawValue)
                .font(.caption.bold())
                .foregroundStyle(AppColor.accent)
            Text(scan.certNumber)
                .font(.caption2.monospaced())
                .lineLimit(1)
            statusBadge(for: scan.status)
        }
        .padding(Spacing.s)
        .frame(width: 92)
        .background(AppColor.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.m))
    }

    private func statusBadge(for status: ScanStatus) -> some View {
        let text: String
        let color: Color
        switch status {
        case .pendingValidation: text = "pending"; color = AppColor.warning
        case .validated:         text = "validated"; color = AppColor.success
        case .validationFailed:  text = "failed"; color = AppColor.danger
        case .manualEntry:       text = "manual"; color = AppColor.accent
        }
        return Text(text)
            .font(.caption2)
            .foregroundStyle(color)
    }
}
