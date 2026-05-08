import SwiftUI

/// Inline destructive-confirmation strip rendered directly under the row
/// being deleted. Replaces the bottom-of-screen `confirmationDialog` action
/// sheet so the choice is visually anchored to the affected item — the
/// vendor sees exactly which lot or slab the cancel/delete buttons apply
/// to without having to glance away from the row.
///
/// The container caller is responsible for presenting/dismissing this view
/// (e.g. via `withAnimation { isPresented = … }`); the view itself just
/// renders the strip and routes button taps through the supplied closures.
struct InlineDeleteConfirmation: View {
    let title: String
    let detail: String?
    let confirmLabel: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    init(
        title: String,
        detail: String? = nil,
        confirmLabel: String = "Delete",
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.confirmLabel = confirmLabel
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(SlabFont.sans(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.text)
                    .accessibilityIdentifier("inline-delete-title")
                if let detail {
                    Text(detail)
                        .font(SlabFont.sans(size: 12))
                        .foregroundStyle(AppColor.muted)
                }
            }
            HStack(spacing: Spacing.s) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(SlabFont.sans(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                                .stroke(AppColor.hairlineStrong, lineWidth: 1)
                        )
                        .foregroundStyle(AppColor.muted)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inline-delete-cancel")

                Button(action: onConfirm) {
                    Text(confirmLabel)
                        .font(SlabFont.sans(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                                .fill(AppColor.negative.opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                                        .stroke(AppColor.negative.opacity(0.6), lineWidth: 1)
                                )
                        )
                        .foregroundStyle(AppColor.negative)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inline-delete-confirm")
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.negative.opacity(0.06))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColor.hairline)
                .frame(height: 1)
        }
        .transition(
            .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            )
        )
    }
}

#Preview {
    VStack(spacing: 0) {
        InlineDeleteConfirmation(
            title: "Delete Big Lot of Doom and all slabs?",
            detail: "This removes the lot and every slab inside it. This can't be undone.",
            confirmLabel: "Delete lot",
            onCancel: {},
            onConfirm: {}
        )
    }
    .padding()
    .background(AppColor.ink)
}
