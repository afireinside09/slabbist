import SwiftUI
import UIKit
import Supabase

struct GradeReportView: View {
    let estimate: GradeEstimateDTO
    var onStarToggle: ((Bool) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var showOtherGraders = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                photos
                SubGradeCard(
                    title: "Centering",
                    score: estimate.subGrades.centering,
                    note: estimate.subGradeNotes.centering,
                    dataPoint: centeringDataPoint
                )
                SubGradeCard(title: "Corners",
                             score: estimate.subGrades.corners,
                             note: estimate.subGradeNotes.corners,
                             dataPoint: nil)
                SubGradeCard(title: "Edges",
                             score: estimate.subGrades.edges,
                             note: estimate.subGradeNotes.edges,
                             dataPoint: nil)
                SubGradeCard(title: "Surface",
                             score: estimate.subGrades.surface,
                             note: estimate.subGradeNotes.surface,
                             dataPoint: nil)

                if let other = estimate.otherGraders {
                    DisclosureGroup("Show other graders", isExpanded: $showOtherGraders) {
                        OtherGradersPanel(bundle: other)
                    }
                    .padding(16)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }

                disclaimer
            }
            .padding(16)
        }
        .navigationTitle("PSA \(formatted(estimate.compositeGrade))")
        .toolbar { toolbarItems }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PSA \(formatted(estimate.compositeGrade))")
                .font(.system(size: 48, weight: .heavy))
                .foregroundStyle(AppColor.gold)
            VerdictPill(verdict: estimate.verdict, confidence: estimate.confidence)
            Text(estimate.verdictReasoning)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var photos: some View {
        HStack(spacing: 12) {
            AsyncGradePhoto(path: estimate.frontThumbPath)
            AsyncGradePhoto(path: estimate.backThumbPath)
        }
        .frame(height: 220)
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
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                onStarToggle?(!estimate.isStarred)
            } label: {
                Image(systemName: estimate.isStarred ? "star.fill" : "star")
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
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
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
