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
            .navigationTitle("Grade")
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
}
