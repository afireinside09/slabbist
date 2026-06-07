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
                        NavigationLink(value: card) {
                            HStack(alignment: .top, spacing: Spacing.m) {
                                thumbnail(for: card)
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(card.cardName).slabRowTitle()
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(card.setName)\(card.cardNumber.map { " · #\($0)" } ?? "")")
                                        .font(SlabFont.mono(size: 13))
                                        .foregroundStyle(AppColor.dim)
                                    if let notes = card.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(SlabFont.sans(size: 12))
                                            .foregroundStyle(AppColor.dim)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(Spacing.m)
                            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Spacing.m)
        }
        .background(AppColor.ink)
        .navigationTitle(subject.name)
        .navigationDestination(for: CameoCardDTO.self) { card in
            CameoCardDetailView(card: card)
        }
        .refreshable { await load() }
        .task { await load() }
    }

    @ViewBuilder
    private func thumbnail(for card: CameoCardDTO) -> some View {
        let size = CGSize(width: 120, height: 168) // ~card aspect, matches other list views
        if let urlString = card.tcgProduct?.imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    thumbnailPlaceholder
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        } else {
            thumbnailPlaceholder
                .frame(width: size.width, height: size.height)
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
            .fill(AppColor.ink)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(AppColor.dim)
            )
    }

    private func load() async {
        isLoading = true; loadFailed = false
        do { cards = try await repo.cards(forSubject: subject.id) }
        catch { loadFailed = true }
        isLoading = false
    }
}
