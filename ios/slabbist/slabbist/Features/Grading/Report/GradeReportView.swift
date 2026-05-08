import SwiftUI
import UIKit
import Supabase

struct GradeReportView: View {
    let estimate: GradeEstimateDTO
    var onStarToggle: ((Bool) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var showOtherGraders = false

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    hero
                    photos
                    subGradesSection
                    if estimate.otherGraders != nil {
                        otherGradersDisclosure
                    }
                    disclaimer
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .navigationTitle("PSA \(formatted(estimate.compositeGrade))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbarItems }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Composite")
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text("PSA")
                    .font(SlabFont.sans(size: 14, weight: .medium))
                    .tracking(2.0)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.dim)
                    .padding(.bottom, 8)
                Text(formatted(estimate.compositeGrade))
                    .font(SlabFont.serif(size: 68))
                    .tracking(-2)
                    .foregroundStyle(AppColor.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            VerdictPill(verdict: estimate.verdict, confidence: estimate.confidence)
            Text(estimate.verdictReasoning)
                .font(SlabFont.sans(size: 14))
                .foregroundStyle(AppColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var photos: some View {
        HStack(spacing: Spacing.m) {
            AsyncGradePhoto(path: estimate.frontThumbPath)
            AsyncGradePhoto(path: estimate.backThumbPath)
        }
        .frame(height: 220)
    }

    private var subGradesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Sub-grades")
            VStack(spacing: Spacing.m) {
                SubGradeCard(
                    title: "Centering",
                    score: estimate.subGrades.centering,
                    note: estimate.subGradeNotes.centering,
                    dataPoint: centeringDataPoint
                )
                SubGradeCard(
                    title: "Corners",
                    score: estimate.subGrades.corners,
                    note: estimate.subGradeNotes.corners,
                    dataPoint: nil
                )
                SubGradeCard(
                    title: "Edges",
                    score: estimate.subGrades.edges,
                    note: estimate.subGradeNotes.edges,
                    dataPoint: nil
                )
                SubGradeCard(
                    title: "Surface",
                    score: estimate.subGrades.surface,
                    note: estimate.subGradeNotes.surface,
                    dataPoint: nil
                )
            }
        }
    }

    private var otherGradersDisclosure: some View {
        SlabCard {
            DisclosureGroup(isExpanded: $showOtherGraders) {
                if let other = estimate.otherGraders {
                    OtherGradersPanel(bundle: other)
                        .padding(.top, Spacing.m)
                }
            } label: {
                Text("Show other graders")
                    .slabRowTitle()
            }
            .tint(AppColor.gold)
            .padding(Spacing.l)
        }
    }

    private var centeringDataPoint: String {
        let f = estimate.centeringFront
        let b = estimate.centeringBack
        return String(
            format: "Front L/R %.0f/%.0f T/B %.0f/%.0f  •  Back L/R %.0f/%.0f T/B %.0f/%.0f",
            f.left * 100, f.right * 100, f.top * 100, f.bottom * 100,
            b.left * 100, b.right * 100, b.top * 100, b.bottom * 100
        )
    }

    private var disclaimer: some View {
        Text("Estimate only — not a guarantee. Real grades depend on submission tier, grader trends, and minor surface defects not visible in photos. Slabbist is not responsible for grading outcomes.")
            .font(SlabFont.sans(size: 11))
            .foregroundStyle(AppColor.dim)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                onStarToggle?(!estimate.isStarred)
            } label: {
                Image(systemName: estimate.isStarred ? "star.fill" : "star")
                    .foregroundStyle(estimate.isStarred ? AppColor.gold : AppColor.text)
            }
            .accessibilityLabel(estimate.isStarred ? "Unstar" : "Star")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(role: .destructive) {
                onDelete?()
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete")
        }
    }

    private func formatted(_ s: Double) -> String {
        s == s.rounded() ? "\(Int(s))" : String(format: "%.1f", s)
    }
}

/// Loads a photo from the `grade-photos` Supabase bucket. Shows a
/// placeholder while loading or after the 30-day purge.
struct AsyncGradePhoto: View {
    let path: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                            .stroke(AppColor.hairline, lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .fill(AppColor.elev)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                            .stroke(AppColor.hairline, lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(AppColor.dim)
                    )
            }
        }
        .task(id: path) { await load() }
    }

    private func load() async {
        do {
            let data = try await AppSupabase.shared.client.storage
                .from("grade-photos")
                .download(path: path)
            image = UIImage(data: data)
        } catch {
            // Leave placeholder in place — purged or unauthorized.
        }
    }
}
