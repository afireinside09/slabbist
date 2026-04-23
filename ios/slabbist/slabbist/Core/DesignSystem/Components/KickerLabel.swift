import SwiftUI

/// Small uppercase category / section label.
/// Appears above nearly every titled block in the design.
struct KickerLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .slabKicker()
    }
}

#Preview("KickerLabel") {
    VStack(alignment: .leading, spacing: 12) {
        KickerLabel("Current lots")
        KickerLabel("Recent comps")
        KickerLabel("Portfolio")
    }
    .padding()
    .background(AppColor.ink)
}
