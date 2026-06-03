import SwiftUI

/// Editable review list for photo-detected certs. Each row is one detected
/// cert for the already-chosen grader; the user fixes misreads, removes
/// false positives, then commits the survivors. Certs already in the lot are
/// shown unchecked with a muted marker (record() would no-op them anyway).
struct PhotoScanReviewView: View {
    let grader: Grader
    let existingCertsInLot: Set<String>
    let onCommit: ([String]) -> Void
    let onRetake: () -> Void

    /// Editable working copy. `included` is the checkbox; pre-set to false
    /// for certs already in the lot.
    @State private var rows: [Row]

    struct Row: Identifiable {
        let id = UUID()
        var cert: String
        var included: Bool
    }

    init(grader: Grader,
         detectedCerts: [String],
         existingCertsInLot: Set<String>,
         onCommit: @escaping ([String]) -> Void,
         onRetake: @escaping () -> Void) {
        self.grader = grader
        self.existingCertsInLot = existingCertsInLot
        self.onCommit = onCommit
        self.onRetake = onRetake
        _rows = State(initialValue: detectedCerts.map {
            Row(cert: $0, included: !existingCertsInLot.contains($0))
        })
    }

    var body: some View {
        SlabbedRoot {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                if rows.isEmpty {
                    emptyState
                } else {
                    list
                }
                Spacer(minLength: 0)
                PrimaryGoldButton(
                    title: addButtonTitle,
                    isEnabled: includedValidCount > 0
                ) {
                    onCommit(commitSet)
                }
                .accessibilityIdentifier("photo-scan-add-button")
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Photo scan")
            Text(rows.isEmpty ? "No \(grader.rawValue) certs found"
                              : "Found \(rows.count) \(grader.rawValue) slab\(rows.count == 1 ? "" : "s")")
                .slabTitle()
        }
    }

    private var emptyState: some View {
        FeatureEmptyState(
            systemImage: "viewfinder",
            title: "Nothing to add",
            subtitle: "No \(grader.rawValue) cert numbers were readable in that photo. Retake with better lighting, or move closer so each label fills more of the frame.",
            steps: []
        )
    }

    private var list: some View {
        SlabCard {
            VStack(spacing: 0) {
                ForEach($rows) { $row in
                    // One view per ForEach element (divider folded inside) so
                    // SwiftUI diffing stays stable on row removal — matches the
                    // openLotsSection pattern in LotsListView.
                    VStack(spacing: 0) {
                        if row.id != rows.first?.id { SlabCardDivider() }
                        rowView($row)
                    }
                }
            }
        }
    }

    private func rowView(_ row: Binding<Row>) -> some View {
        let cert = row.wrappedValue.cert
        let alreadyInLot = existingCertsInLot.contains(cert)
        let formatProblem = validate(cert)
        return HStack(spacing: Spacing.m) {
            Button {
                row.wrappedValue.included.toggle()
            } label: {
                Image(systemName: row.wrappedValue.included ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(row.wrappedValue.included ? AppColor.gold : AppColor.dim)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.wrappedValue.included ? "Exclude \(cert)" : "Include \(cert)")

            TextField("", text: row.cert)
                .keyboardType(grader == .TAG ? .asciiCapable : .numberPad)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .font(SlabFont.mono(size: 15))
                .foregroundStyle(AppColor.text)
                .tint(AppColor.gold)

            Spacer()

            if alreadyInLot {
                Text("in lot")
                    .font(SlabFont.mono(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.dim)
            } else if let formatProblem {
                Text(formatProblem)
                    .font(SlabFont.mono(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.negative)
            }

            Button {
                rows.removeAll { $0.id == row.wrappedValue.id }
            } label: {
                Image(systemName: "xmark")
                    .font(SlabFont.sans(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.dim)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(cert)")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
    }

    /// Included rows whose edited cert still passes format validation — the
    /// exact set committed to the lot. Computed once, reused by count + title.
    private var commitSet: [String] {
        rows.filter { $0.included && validate($0.cert) == nil }.map(\.cert)
    }
    private var includedValidCount: Int { commitSet.count }
    private var addButtonTitle: String {
        includedValidCount == 0 ? "Add to lot" : "Add \(includedValidCount) to lot"
    }

    /// Per-grader format check. Mirrors `ManualEntrySheet.validate` — short
    /// message used as a row flag rather than a blocking error.
    private func validate(_ cert: String) -> String? {
        switch grader {
        case .PSA:
            return (cert.allSatisfy(\.isNumber) && (8...9).contains(cert.count)) ? nil : "8–9 digits"
        case .BGS, .CGC:
            return (cert.allSatisfy(\.isNumber) && cert.count == 10) ? nil : "10 digits"
        case .SGC:
            return (cert.allSatisfy(\.isNumber) && (7...8).contains(cert.count)) ? nil : "7–8 digits"
        case .TAG:
            let alnum = cert.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
            return (alnum && (10...12).contains(cert.count)) ? nil : "10–12 chars"
        }
    }
}
