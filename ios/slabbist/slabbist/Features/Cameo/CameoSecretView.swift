import SwiftUI

/// The hidden "Pokemon Cameos" page: a full-screen, tab-less cover reached only via the
/// Psyduck easter egg. Search/browse every cameo subject; drill into one to see
/// its cards. Dismisses via the X — there is intentionally no tab bar.
struct CameoSecretView: View {
    var repo: CameoRepository = CameoRepository()
    let onClose: () -> Void

    @State private var query = ""
    @State private var subjects: [CameoSubjectDTO] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.s) {
                    KickerLabel("Pokemon Cameos")
                        .padding(.horizontal, Spacing.m)
                        .padding(.top, Spacing.s)

                    if isLoading {
                        ProgressView().tint(AppColor.gold)
                            .frame(maxWidth: .infinity).padding(.top, Spacing.l)
                    } else if subjects.isEmpty {
                        Text("No cameos match \"\(query)\".")
                            .font(SlabFont.sans(size: 14))
                            .foregroundStyle(AppColor.dim)
                            .padding(.horizontal, Spacing.m)
                    } else {
                        ForEach(subjects) { subject in
                            NavigationLink(value: subject) {
                                CameoSubjectRow(subject: subject)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, Spacing.l)
            }
            .background(AppColor.ink)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search cameo Pokémon or Trainers")
            .navigationDestination(for: CameoSubjectDTO.self) { subject in
                CameoSubjectDetailView(subject: subject, repo: repo)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onClose() } label: { Image(systemName: "xmark") }
                        .tint(AppColor.gold)
                        .accessibilityLabel("Close Pokemon Cameos")
                }
            }
        }
        // .task(id:) re-runs whenever query changes and cancels the prior
        // in-flight task automatically — no manual Task storage needed.
        .task(id: query) { await runSearch(query) }
    }

    private func runSearch(_ text: String) async {
        isLoading = subjects.isEmpty
        do {
            let result = try await repo.searchSubjects(text)
            if !Task.isCancelled { subjects = result }
        } catch {
            if !Task.isCancelled { subjects = [] }
        }
        isLoading = false
    }
}

private struct CameoSubjectRow: View {
    let subject: CameoSubjectDTO

    var body: some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name).slabRowTitle()
                Text(subtitle)
                    .font(SlabFont.mono(size: 12))
                    .foregroundStyle(AppColor.dim)
            }
            Spacer()
            Text("\(subject.cardCount)")
                .font(SlabFont.mono(size: 13))
                .foregroundStyle(AppColor.gold)
            Image(systemName: "chevron.right").foregroundStyle(AppColor.dim)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }

    private var subtitle: String {
        if let ndex = subject.ndex { return "No. \(ndex)" }
        if let region = subject.region { return region }
        return "Trainer"
    }
}
