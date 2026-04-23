import SwiftUI

struct NewLotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = defaultName()
    @State private var error: String?

    let onCreate: (String) throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Lot name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(AppColor.danger)
                    }
                }
            }
            .navigationTitle("New bulk scan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start scanning") {
                        do {
                            try onCreate(name.trimmingCharacters(in: .whitespaces))
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private static func defaultName() -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return "Bulk – \(fmt.string(from: Date()))"
    }
}
