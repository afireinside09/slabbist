import SwiftUI

/// Sheet for creating or editing a vendor. Mirrors the visual language of
/// `ManualPriceSheet` (existing in Features/Scanning).
struct VendorEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: Vendor?
    let onSave: (UUID?, String, String?, String?, String?) throws -> Void

    @State private var displayName: String = ""
    @State private var contactMethod: String = "phone"
    @State private var contactValue: String = ""
    @State private var notes: String = ""
    @State private var error: String?

    private static let methods = ["phone", "email", "instagram", "in_person", "other"]

    init(initial: Vendor?, onSave: @escaping (UUID?, String, String?, String?, String?) throws -> Void) {
        self.initial = initial
        self.onSave = onSave
        _displayName = State(initialValue: initial?.displayName ?? "")
        _contactMethod = State(initialValue: initial?.contactMethod ?? "phone")
        _contactValue = State(initialValue: initial?.contactValue ?? "")
        _notes = State(initialValue: initial?.notes ?? "")
    }

    /// Public so unit tests can exercise the trim + empty-rejection rule.
    static func normalize(displayName: String) -> String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                topBar
                header
                form
                if let error {
                    Text(error)
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.negative)
                        .accessibilityIdentifier("vendor-edit-error")
                }
                Spacer()
                PrimaryGoldButton(
                    title: initial == nil ? "Save vendor" : "Update vendor",
                    isEnabled: Self.normalize(displayName: displayName) != nil
                ) { submit() }
                .accessibilityIdentifier("vendor-edit-save")
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
    }

    private var topBar: some View {
        HStack {
            SecondaryIconButton(systemIcon: "xmark", accessibilityLabel: "Cancel") { dismiss() }
            Spacer()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel(initial == nil ? "New vendor" : "Edit vendor")
            Text(initial?.displayName ?? "Add a vendor").slabTitle()
        }
    }

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            field(label: "Display name", text: $displayName, identifier: "vendor-edit-name")
            Picker("Contact method", selection: $contactMethod) {
                ForEach(Self.methods, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("vendor-edit-method")
            field(label: "Contact value", text: $contactValue, identifier: "vendor-edit-value")
            field(label: "Notes", text: $notes, identifier: "vendor-edit-notes")
        }
    }

    private func field(label: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            KickerLabel(label)
            SlabCard {
                TextField(label, text: text)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.md)
                    .accessibilityIdentifier(identifier)
            }
        }
    }

    private func submit() {
        guard let name = Self.normalize(displayName: displayName) else {
            error = "Enter a display name."
            return
        }
        do {
            try onSave(
                initial?.id,
                name,
                contactMethod,
                contactValue.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                notes.trimmingCharacters(in: .whitespaces).nilIfEmpty
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
