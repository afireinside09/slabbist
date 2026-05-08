import SwiftUI

struct NewLotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = defaultName()
    @State private var error: String?

    let onCreate: (String) throws -> Void

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                topBar
                header
                SlabCard {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(AppColor.dim)
                            .frame(width: 18)
                        TextField("", text: $name,
                                  prompt: Text("Lot name").foregroundStyle(AppColor.dim))
                            .textInputAutocapitalization(.words)
                            .foregroundStyle(AppColor.text)
                            .tint(AppColor.gold)
                            .accessibilityIdentifier("new-lot-name-field")
                        if !name.isEmpty {
                            Button {
                                name = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppColor.dim)
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Clear lot name")
                            .accessibilityIdentifier("new-lot-clear-button")
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.md)
                }
                if let error {
                    Text(error)
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.negative)
                }
                Spacer()
                PrimaryGoldButton(
                    title: "Create lot",
                    isEnabled: !trimmedName.isEmpty
                ) {
                    do {
                        try onCreate(trimmedName)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .accessibilityIdentifier("new-lot-create-button")
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .ambientGoldBlob(.topTrailing)
    }

    private var topBar: some View {
        HStack {
            SecondaryIconButton(systemIcon: "xmark", accessibilityLabel: "Cancel") {
                dismiss()
            }
            Spacer()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("New lot")
            Text("Start scanning").slabTitle()
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private static func defaultName() -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return "Bulk – \(fmt.string(from: Date()))"
    }
}

#Preview {
    NewLotSheet { _ in }
}
