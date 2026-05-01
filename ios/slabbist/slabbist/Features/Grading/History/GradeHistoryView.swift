import SwiftUI

struct GradeHistoryView: View {
    @State private var vm: GradeHistoryViewModel
    @State private var openCapture = false

    let currentUserId: UUID

    init(repo: any GradeEstimateRepository, currentUserId: UUID) {
        _vm = State(initialValue: GradeHistoryViewModel(repo: repo))
        self.currentUserId = currentUserId
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $vm.filter) {
                        Text("All").tag(GradeHistoryViewModel.Filter.all)
                        Text("Starred").tag(GradeHistoryViewModel.Filter.starred)
                    }
                    .pickerStyle(.segmented)
                }
                if vm.visibleRows.isEmpty {
                    Section {
                        FeatureEmptyState(
                            systemImage: "checkmark.seal",
                            title: emptyTitle,
                            subtitle: emptySubtitle,
                            steps: emptySteps
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: Spacing.m, leading: 0, bottom: Spacing.m, trailing: 0))
                    }
                } else {
                    ForEach(vm.visibleRows) { e in
                        NavigationLink {
                            GradeReportView(
                                estimate: e,
                                onStarToggle: { newValue in
                                    Task { await vm.toggleStar(id: e.id, starred: newValue) }
                                },
                                onDelete: {
                                    Task { await vm.delete(id: e.id) }
                                }
                            )
                        } label: {
                            GradeHistoryRow(estimate: e)
                        }
                    }
                }
            }
            .navigationTitle("Pre-grade")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openCapture = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                    }
                    .accessibilityLabel("Grade a card")
                }
            }
            .task { await vm.load() }
            .sheet(isPresented: $openCapture) {
                NavigationStack {
                    GradingCaptureView(
                        viewModel: GradingCaptureViewModel(
                            repo: AppRepositories.live().gradeEstimates,
                            uploader: GradePhotoUploader(),
                            userId: currentUserId
                        ),
                        onComplete: { _ in
                            openCapture = false
                            Task { await vm.load() }
                        }
                    )
                }
            }
        }
    }

    /// "Starred" reads differently than "All" — when the user has
    /// graded zero cards we explain the feature; when they've graded
    /// some but starred none we just nudge them to star.
    private var emptyTitle: String {
        switch vm.filter {
        case .all:     return "Pre-grade a slab"
        case .starred: return "No starred grades"
        }
    }

    private var emptySubtitle: String {
        switch vm.filter {
        case .all:
            return "Slabbist photographs a raw card and predicts the PSA grade you'd get back — corners, edges, surface, centering."
        case .starred:
            return "Tap the star on any grade report to keep it pinned here for quick reference."
        }
    }

    private var emptySteps: [String] {
        switch vm.filter {
        case .all:
            return [
                "Tap the camera in the top right to start a capture.",
                "Frame the front, back, corners, and edges as prompted.",
                "Slabbist returns a 1–10 estimate per criterion plus a composite.",
            ]
        case .starred:
            return []
        }
    }
}
