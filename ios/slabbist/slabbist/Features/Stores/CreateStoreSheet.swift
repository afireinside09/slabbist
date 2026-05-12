import SwiftUI

/// Onboarding sheet shown when the signed-in user has no store yet.
/// Mirrors `NewLotSheet` visually so the rest of the app's setup
/// surfaces feel consistent. The caller passes an async `onCreate`
/// closure that performs the RPC + rehydration; the sheet dismisses
/// only after `onCreate` returns without throwing.
struct CreateStoreSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = "My Store"
    @State private var error: String?
    @State private var isSubmitting = false

    let onCreate: (String) async throws -> Void

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                topBar
                header
                SlabCard {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "storefront")
                            .foregroundStyle(AppColor.dim)
                            .frame(width: 18)
                        TextField("", text: $name,
                                  prompt: Text("Store name").foregroundStyle(AppColor.dim))
                            .textInputAutocapitalization(.words)
                            .foregroundStyle(AppColor.text)
                            .tint(AppColor.gold)
                            .disabled(isSubmitting)
                            .accessibilityIdentifier("create-store-name-field")
                        if !name.isEmpty && !isSubmitting {
                            Button {
                                name = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppColor.dim)
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Clear store name")
                            .accessibilityIdentifier("create-store-clear-button")
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.md)
                }
                Text("Your lots, scans, and offers live under this store. You can rename it later in Settings.")
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.dim)
                if let error {
                    Text(error)
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.negative)
                }
                Spacer()
                PrimaryGoldButton(
                    title: "Create store",
                    isLoading: isSubmitting,
                    isEnabled: !trimmedName.isEmpty && !isSubmitting
                ) {
                    Task { await submit() }
                }
                .accessibilityIdentifier("create-store-submit-button")
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .ambientGoldBlob(.topTrailing)
        .interactiveDismissDisabled(isSubmitting)
    }

    private var topBar: some View {
        HStack {
            SecondaryIconButton(systemIcon: "xmark", accessibilityLabel: "Cancel") {
                dismiss()
            }
            .disabled(isSubmitting)
            Spacer()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Set up")
            Text("Name your store").slabTitle()
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private func submit() async {
        let name = trimmedName
        guard !name.isEmpty else { return }
        error = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await onCreate(name)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    CreateStoreSheet { _ in }
}
