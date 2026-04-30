import SwiftUI

/// Manual fallback when OCR can't read a slab (poor lighting, glare, damaged
/// label). The user picks a grader, types the cert number, and the result
/// flows through the same `BulkScanViewModel.record(candidate:)` path as an
/// OCR'd capture — meaning cert-lookup + comp fetch fire automatically.
struct ManualEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var grader: Grader = .PSA
    @State private var certNumber: String = ""
    @State private var error: String?
    @FocusState private var certFieldFocused: Bool

    let onSubmit: (CertCandidate) throws -> Void

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                topBar
                header
                graderPicker
                certCard
                if let error {
                    Text(error)
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.negative)
                }
                Spacer()
                PrimaryGoldButton(
                    title: "Add to lot",
                    isEnabled: !trimmedCert.isEmpty
                ) {
                    submit()
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .onAppear { certFieldFocused = true }
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
            KickerLabel("Manual entry")
            Text("Enter slab details").slabTitle()
        }
    }

    private var graderPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Grader")
            Picker("Grader", selection: $grader) {
                ForEach(Grader.allCases, id: \.self) { g in
                    Text(g.rawValue).tag(g)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var certCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Cert number")
            SlabCard {
                HStack(spacing: Spacing.m) {
                    Image(systemName: "number")
                        .foregroundStyle(AppColor.dim)
                        .frame(width: 18)
                    TextField("",
                              text: $certNumber,
                              prompt: Text(certPrompt).foregroundStyle(AppColor.dim))
                        .keyboardType(certKeyboardType)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .focused($certFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { submit() }
                        .foregroundStyle(AppColor.text)
                        .tint(AppColor.gold)
                        .accessibilityIdentifier("manual-cert-field")
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.md)
            }
        }
    }

    /// PSA/BGS/CGC/SGC certs are pure digits — number pad is the right
    /// keyboard. TAG certs are alphanumeric (10–12 chars), so number pad
    /// would lock the user out of valid characters; fall back to the ASCII
    /// keyboard for that grader only.
    private var certKeyboardType: UIKeyboardType {
        switch grader {
        case .PSA, .BGS, .CGC, .SGC: return .numberPad
        case .TAG:                    return .asciiCapable
        }
    }

    private var certPrompt: String {
        switch grader {
        case .PSA: return "8–9 digits"
        case .BGS, .CGC: return "10 digits"
        case .SGC: return "7–8 digits"
        case .TAG: return "10–12 characters"
        }
    }

    private var trimmedCert: String {
        certNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        let cert = trimmedCert
        guard !cert.isEmpty else { return }
        let candidate = CertCandidate(
            grader: grader,
            certNumber: cert,
            confidence: 1.0,
            rawText: "manual entry"
        )
        do {
            try onSubmit(candidate)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    ManualEntrySheet { _ in }
}
