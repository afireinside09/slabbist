import SwiftUI
import PhotosUI
import UIKit

/// Standalone centering tool: import a card photo, measure its centering with
/// the same editor the pre-grade flow uses, read the result. Ephemeral — no
/// persistence. Faithful to the "static image" premise of dedicated centering
/// apps; capture-from-camera can be added later.
struct StandaloneCenteringView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = StandaloneCenteringModel()
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Measure centering")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                    }
                }
                .background(AppColor.ink.ignoresSafeArea())
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await model.loadImage(img)
                }
                photoItem = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image = model.importedImage {
            if let result = model.result {
                resultCard(image: image, ratios: result)
            } else {
                CenteringEditorView(
                    image: image,
                    guides: model.seedGuides,
                    title: "Centering",
                    confirmLabel: "Measure",
                    onConfirm: { ratios in model.result = ratios },
                    onCancel: { model.clear() }
                )
            }
        } else {
            pickPrompt
        }
    }

    private var pickPrompt: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "ruler")
                .font(SlabFont.sans(size: 36, weight: .regular))
                .foregroundStyle(AppColor.gold)
            VStack(spacing: Spacing.s) {
                Text("Measure a card's centering")
                    .slabRowTitle()
                Text("Pick a clear, straight-on photo of the card. Drag the guides to the card edge and the inner frame to read its centering.")
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose a photo", systemImage: "photo.on.rectangle")
                    .font(SlabFont.sans(size: 15, weight: .semibold))
                    .foregroundStyle(AppColor.ink)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.m)
                    .background(Capsule().fill(AppColor.gold))
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultCard(image: UIImage, ratios: CenteringRatios) -> some View {
        let ceiling = CenteringGuideMath.psaCenteringCeiling(ratios)
        return VStack(spacing: Spacing.xl) {
            SlabCard {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    KickerLabel("Centering")
                    CenteringReadoutView(ratios: ratios)
                    Text("Centering alone allows up to PSA \(ceiling.grade). Centering caps a grade — it can't lift corners, edges, or surface.")
                        .font(SlabFont.sans(size: 13))
                        .foregroundStyle(AppColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: Spacing.m) {
                ShareLink(item: shareText(ratios: ratios, ceiling: ceiling.grade)) {
                    Label("Share result", systemImage: "square.and.arrow.up")
                        .font(SlabFont.sans(size: 15, weight: .semibold))
                        .foregroundStyle(AppColor.text)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: Radius.m).fill(AppColor.elev2))
                }
                SecondaryButton(title: "Adjust again") { model.result = nil }
                SecondaryButton(title: "Measure another") { model.clear() }
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func shareText(ratios: CenteringRatios, ceiling: Int) -> String {
        let lr = "\(Int((ratios.left * 100).rounded()))/\(Int((ratios.right * 100).rounded()))"
        let tb = "\(Int((ratios.top * 100).rounded()))/\(Int((ratios.bottom * 100).rounded()))"
        return "Centering — L/R \(lr), T/B \(tb) (allows up to PSA \(ceiling)). Measured with Slabbist."
    }
}
