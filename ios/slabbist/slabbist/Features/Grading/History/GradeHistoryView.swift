import SwiftUI

struct GradeHistoryView: View {
    @State private var vm: GradeHistoryViewModel
    /// Single source of truth for the modal on this screen. One sheet
    /// modifier swaps between capture and report, so completing a capture
    /// (capture → report) is a content swap on ONE sheet rather than
    /// dismissing one sheet while presenting another in the same tick — the
    /// latter races UIKit's presentation controller and silently drops the
    /// report.
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case capture
        case report(GradeEstimateDTO)
        var id: String {
            switch self {
            case .capture:            return "capture"
            case let .report(estimate): return "report-\(estimate.id.uuidString)"
            }
        }
    }

    let currentUserId: UUID

    init(repo: any GradeEstimateRepository, currentUserId: UUID) {
        _vm = State(initialValue: GradeHistoryViewModel(repo: repo))
        self.currentUserId = currentUserId
    }

    /// Two-way binding the action-error alert drives. Attached to each
    /// GradeReportView context (pushed and sheet) since star/delete failures
    /// only originate there.
    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { vm.actionError != nil },
            set: { if !$0 { vm.actionError = nil } }
        )
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
                switch vm.loadState {
                case .loading:
                    Section { loadingState }
                case .failed:
                    Section { failedState }
                case .loaded:
                    if vm.visibleRows.isEmpty {
                        Section { emptyState }
                    } else {
                        ForEach(vm.visibleRows) { e in
                            NavigationLink {
                                // Pushed browse path: delete doesn't auto-pop
                                // (unchanged from before); a failure surfaces
                                // via the attached alert.
                                reportView(for: e, onDeleted: {})
                            } label: {
                                GradeHistoryRow(estimate: e)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pre-grade")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        activeSheet = .capture
                    } label: {
                        Image(systemName: "camera.viewfinder")
                    }
                    .accessibilityLabel("Grade a card")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsGearButton()
                }
            }
            .task { await vm.load() }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .capture:
                    NavigationStack {
                        GradingCaptureView(
                            viewModel: GradingCaptureViewModel(
                                repo: AppRepositories.live().gradeEstimates,
                                uploader: GradePhotoUploader(),
                                userId: currentUserId
                            ),
                            onComplete: { estimate in
                                // Swap this same sheet from capture to report
                                // so the earned result is shown in-flow, and
                                // refresh the list underneath so the new row is
                                // there when the user taps Done.
                                activeSheet = .report(estimate)
                                Task { await vm.load() }
                            }
                        )
                    }
                case let .report(estimate):
                    NavigationStack {
                        reportView(for: estimate, onDeleted: { activeSheet = nil })
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Done") { activeSheet = nil }
                                }
                            }
                    }
                }
            }
        }
    }

    /// GradeReportView wired to the view model, with star/delete failures
    /// surfaced via an alert in whichever context (pushed or sheet) is
    /// foreground. `onDeleted` runs only on a successful delete.
    @ViewBuilder
    private func reportView(
        for estimate: GradeEstimateDTO,
        onDeleted: @escaping () -> Void
    ) -> some View {
        GradeReportView(
            estimate: estimate,
            onStarToggle: { newValue in
                Task { await vm.toggleStar(id: estimate.id, starred: newValue) }
            },
            onDelete: {
                Task {
                    await vm.delete(id: estimate.id)
                    if vm.actionError == nil { onDeleted() }
                }
            }
        )
        .alert(
            "Something went wrong",
            isPresented: actionErrorBinding,
            actions: { Button("OK", role: .cancel) { vm.actionError = nil } },
            message: { Text(vm.actionError ?? "") }
        )
    }

    private var loadingState: some View {
        HStack(spacing: Spacing.m) {
            ProgressView()
            Text("Loading your grades…")
                .font(SlabFont.sans(size: 14))
                .foregroundStyle(AppColor.muted)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, Spacing.xl)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var failedState: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "wifi.exclamationmark")
                .font(SlabFont.sans(size: 28, weight: .regular))
                .foregroundStyle(AppColor.muted)
            Text("Couldn't load your grades")
                .slabRowTitle()
            Text("Check your connection and try again.")
                .font(SlabFont.sans(size: 13))
                .foregroundStyle(AppColor.muted)
                .multilineTextAlignment(.center)
            SecondaryButton(title: "Retry") {
                Task { await vm.load() }
            }
            .padding(.top, Spacing.s)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var emptyState: some View {
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
                "Tap the camera in the top left to start a capture.",
                "Frame the front, back, corners, and edges as prompted.",
                "Slabbist returns a 1–10 estimate per criterion plus a composite.",
            ]
        case .starred:
            return []
        }
    }
}
