import SwiftUI

/// Lists every card (incl. reprints) that features one cameo subject, each with
/// a TCGplayer search-affiliate button. Loads its own cards on appear.
struct CameoSubjectDetailView: View {
    let subject: CameoSubjectDTO
    var repo: CameoRepository = CameoRepository()

    @State private var cards: [CameoCardDTO] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.m) {
                if isLoading {
                    ProgressView().tint(AppColor.gold).frame(maxWidth: .infinity)
                } else if loadFailed {
                    Text("Couldn't load cards. Pull down to retry.")
                        .font(SlabFont.sans(size: 14))
                        .foregroundStyle(AppColor.dim)
                } else {
                    ForEach(cards) { card in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(card.cardName).slabRowTitle()
                            Text("\(card.setName)\(card.cardNumber.map { " · #\($0)" } ?? "")")
                                .font(SlabFont.mono(size: 13))
                                .foregroundStyle(AppColor.dim)
                            if let notes = card.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(SlabFont.sans(size: 12))
                                    .foregroundStyle(AppColor.dim)
                            }
                            TCGPlayerSearchLinkButton(query: "\(card.cardName) \(card.setName)")
                        }
                        .padding(Spacing.m)
                        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                    }
                }
            }
            .padding(Spacing.m)
        }
        .background(AppColor.ink)
        .navigationTitle(subject.name)
        .task { await load() }
    }

    private func load() async {
        isLoading = true; loadFailed = false
        do { cards = try await repo.cards(forSubject: subject.id) }
        catch { loadFailed = true }
        isLoading = false
    }
}
