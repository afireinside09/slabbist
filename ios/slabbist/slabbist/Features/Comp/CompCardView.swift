import SwiftUI
import SwiftData

/// Two-source comp card. The hero number is the *reconciled* headline
/// (server-computed average of PPT + Poketrace when both succeed,
/// single-source otherwise) sourced off `Scan.reconciledHeadlinePriceCents`.
///
/// Below the hero, a "Sources" strip shows each provider's number side
/// by side so the operator can sanity-check the reconciliation. The
/// PPT-shaped grade ladder, sparkline, caveat, and "View on Pokemon
/// Price Tracker" footer all continue to read from the PPT snapshot —
/// Poketrace contributes its own row on the sources strip and an
/// alternate sparkline series via the segmented toggle.
struct CompCardView: View {
    let scan: Scan
    let pptSnapshot: GradedMarketSnapshot?
    let poketraceSnapshot: GradedMarketSnapshot?

    /// Which provider feeds the inline sparkline. Defaults to PPT;
    /// switches to Poketrace only when the operator taps the segment.
    @State private var sparklineSource: SparklineSource = .ppt

    var body: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: 0) {
                heroRow
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, Spacing.l)
                    .padding(.bottom, Spacing.md)
                SlabCardDivider()
                sourcesRow
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.md)
                if hasAnySparklineHistory {
                    SlabCardDivider()
                    sparklineSection
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                if !ladderTiers.isEmpty {
                    SlabCardDivider()
                    ladderRail
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                if let caveat = caveatMessage {
                    SlabCardDivider()
                    caveatRow(caveat)
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                SlabCardDivider()
                footerRow
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.md)
            }
        }
    }

    // MARK: - Hero (reconciled)

    private var heroRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(reconciledHeadlineText)
                    .font(SlabFont.serif(size: 40))
                    .tracking(-1)
                    .foregroundStyle(AppColor.text)
                Text(reconciledCaption)
                    .font(SlabFont.sans(size: 11, weight: .medium))
                    .tracking(2.0)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.dim)
            }
            Spacer()
        }
    }

    private var reconciledHeadlineText: String {
        guard let cents = scan.reconciledHeadlinePriceCents else { return "—" }
        return formatCents(cents)
    }

    /// Caption beneath the hero. Prefers `scan.reconciledSource` (set by
    /// the server-side reconciliation rule) and falls back to inferring
    /// from snapshot presence for legacy rows that pre-date the source
    /// being plumbed through.
    private var reconciledCaption: String {
        let graderTier = "\(scan.grader.rawValue) \(scan.grade ?? "")".trimmingCharacters(in: .whitespaces)
        let suffix = graderTier.isEmpty ? "" : " · \(graderTier)"
        let lead: String
        switch scan.reconciledSource {
        case "avg":
            lead = "avg of 2 sources"
        case "ppt-only":
            lead = "PPT only"
        case "poketrace-only":
            lead = "Poketrace only"
        case "poketrace-preferred":
            // Surface the sale count so the operator sees *why* Poketrace
            // wins over the simple average — "n=57" makes the override
            // legible without explaining the rule in copy.
            if let n = poketraceSnapshot?.ptSaleCount {
                return "Poketrace · n=\(n)\(suffix)"
            }
            lead = "Poketrace preferred"
        default:
            // Legacy fallback when reconciledSource hasn't been written.
            let pptOK = pptSnapshot?.headlinePriceCents != nil
            let ptOK  = poketraceSnapshot?.ptAvgCents != nil
            switch (pptOK, ptOK) {
            case (true,  true):  lead = "avg of 2 sources"
            case (true,  false): lead = "PPT only"
            case (false, true):  lead = "Poketrace only"
            case (false, false): return "no price data"
            }
        }
        return "\(lead)\(suffix)"
    }

    // MARK: - Sources strip

    private var sourcesRow: some View {
        HStack(alignment: .top, spacing: Spacing.l) {
            SourcePriceCell(
                title: "PPT",
                priceCents: pptSnapshot?.headlinePriceCents,
                accessoryLine1: nil,
                accessoryLine2: nil,
                confidence: nil
            )
            Rectangle()
                .fill(AppColor.hairline)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            SourcePriceCell(
                title: "Poketrace",
                priceCents: poketraceSnapshot?.ptAvgCents,
                accessoryLine1: priceRange(snapshot: poketraceSnapshot),
                accessoryLine2: salesAndTrend(snapshot: poketraceSnapshot),
                confidence: poketraceSnapshot?.ptConfidence
            )
        }
        // Fixed minimum so a thin Poketrace cell (no range / no count)
        // doesn't collapse the divider against the PPT cell.
        .frame(minHeight: 44)
    }

    private func priceRange(snapshot: GradedMarketSnapshot?) -> String? {
        guard let s = snapshot, let lo = s.ptLowCents, let hi = s.ptHighCents else { return nil }
        return "\(formatCentsCompact(lo))–\(formatCentsCompact(hi))"
    }

    private func salesAndTrend(snapshot: GradedMarketSnapshot?) -> String? {
        guard let s = snapshot else { return nil }
        var parts: [String] = []
        if let n = s.ptSaleCount { parts.append("n=\(n)") }
        if let trend = s.ptTrend { parts.append(trendChevron(trend)) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func trendChevron(_ trend: String) -> String {
        switch trend {
        case "up":   return "▲"
        case "down": return "▼"
        default:     return "–"
        }
    }

    // MARK: - Sparkline + source toggle

    private var pptHistoryPoints: [PriceHistoryPoint] {
        (pptSnapshot?.priceHistory ?? []).sorted { $0.ts < $1.ts }
    }

    private var poketraceHistoryPoints: [PriceHistoryPoint] {
        (poketraceSnapshot?.priceHistory ?? []).sorted { $0.ts < $1.ts }
    }

    private var hasAnySparklineHistory: Bool {
        !pptHistoryPoints.isEmpty || !poketraceHistoryPoints.isEmpty
    }

    private var activeSparklinePoints: [PriceHistoryPoint] {
        switch sparklineSource {
        case .ppt:       return pptHistoryPoints
        case .poketrace: return poketraceHistoryPoints
        }
    }

    @ViewBuilder
    private var sparklineSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            // Show the toggle only when both providers have history; if
            // only one has data, just render the chart.
            if !pptHistoryPoints.isEmpty && !poketraceHistoryPoints.isEmpty {
                Picker("History source", selection: $sparklineSource) {
                    Text("PPT").tag(SparklineSource.ppt)
                    Text("Poketrace").tag(SparklineSource.poketrace)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Sparkline source")
            }
            if !activeSparklinePoints.isEmpty {
                CompSparklineView(points: activeSparklinePoints)
            }
        }
        .onAppear { reconcileSparklineSource() }
        .onChange(of: pptHistoryPoints.isEmpty) { _, _ in reconcileSparklineSource() }
        .onChange(of: poketraceHistoryPoints.isEmpty) { _, _ in reconcileSparklineSource() }
    }

    /// If the currently-selected source has no points but the other
    /// does, swap to the populated one so the user never sees an empty
    /// chart inside an open card.
    private func reconcileSparklineSource() {
        if sparklineSource == .ppt, pptHistoryPoints.isEmpty, !poketraceHistoryPoints.isEmpty {
            sparklineSource = .poketrace
        } else if sparklineSource == .poketrace, poketraceHistoryPoints.isEmpty, !pptHistoryPoints.isEmpty {
            sparklineSource = .ppt
        }
    }

    enum SparklineSource: String, CaseIterable, Identifiable {
        case ppt, poketrace
        var id: String { rawValue }
    }

    // MARK: - Grade ladder (PPT-shaped)

    private struct Tier: Identifiable {
        let id: String
        let label: String
        let cents: Int64
        let isHeadline: Bool
    }

    /// Ordered tiers in the ladder rail. The cell matching the scan's
    /// (gradingService, grade) gets a gold border.
    private var ladderTiers: [Tier] {
        guard let snapshot = pptSnapshot else { return [] }
        let entries: [(id: String, label: String, cents: Int64?, headlineKey: (service: String, grade: String)?)] = [
            ("loose",    "Raw",     snapshot.loosePriceCents,     nil),
            ("psa_7",    "PSA 7",   snapshot.psa7PriceCents,      ("PSA", "7")),
            ("psa_8",    "PSA 8",   snapshot.psa8PriceCents,      ("PSA", "8")),
            ("psa_9",    "PSA 9",   snapshot.psa9PriceCents,      ("PSA", "9")),
            ("psa_9_5",  "PSA 9.5", snapshot.psa9_5PriceCents,    ("PSA", "9.5")),
            ("psa_10",   "PSA 10",  snapshot.psa10PriceCents,     ("PSA", "10")),
            ("bgs_10",   "BGS 10",  snapshot.bgs10PriceCents,     ("BGS", "10")),
            ("cgc_10",   "CGC 10",  snapshot.cgc10PriceCents,     ("CGC", "10")),
            ("sgc_10",   "SGC 10",  snapshot.sgc10PriceCents,     ("SGC", "10")),
        ]
        return entries.compactMap { e in
            guard let cents = e.cents else { return nil }
            let isHeadline = e.headlineKey.map {
                $0.service == snapshot.gradingService && $0.grade == snapshot.grade
            } ?? false
            return Tier(id: e.id, label: e.label, cents: cents, isHeadline: isHeadline)
        }
    }

    private var ladderRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(ladderTiers) { tier in
                    tierCell(tier)
                }
            }
        }
    }

    private func tierCell(_ tier: Tier) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(tier.label)
                .font(SlabFont.sans(size: 10, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(AppColor.dim)
            Text(formatCentsCompact(tier.cents))
                .font(SlabFont.mono(size: 14, weight: .medium))
                .foregroundStyle(AppColor.text)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tier.isHeadline ? AppColor.gold : AppColor.dim.opacity(0.3),
                        lineWidth: tier.isHeadline ? 1.5 : 1)
        )
    }

    // MARK: - Caveat (PPT-driven)

    /// One of three states: stale fallback, headline tier missing for a
    /// supported (grader, grade), or unsupported (grader, grade) entirely.
    /// Driven by the PPT snapshot — Poketrace gracefully degrades inside
    /// its source cell instead.
    private var caveatMessage: String? {
        guard let snapshot = pptSnapshot else { return nil }
        if snapshot.isStaleFallback {
            return "Cached — Pokemon Price Tracker unavailable"
        }
        if snapshot.headlinePriceCents == nil {
            // Distinguish "supported but no value" (PSA 10 with no sales)
            // from "unsupported (TAG / sub-PSA-7)".
            if isSupportedTier(service: snapshot.gradingService, grade: snapshot.grade) {
                return "Pokemon Price Tracker has no \(snapshot.gradingService) \(snapshot.grade) sales for this card yet — showing the rest of the ladder."
            } else {
                return "Pokemon Price Tracker hasn't logged \(snapshot.gradingService) \(snapshot.grade) sales — showing the rest of the ladder."
            }
        }
        return nil
    }

    private func isSupportedTier(service: String, grade: String) -> Bool {
        switch (service, grade) {
        case ("PSA", "10"), ("PSA", "9.5"), ("PSA", "9"), ("PSA", "8"), ("PSA", "7"):
            return true
        case ("BGS", "10"), ("CGC", "10"), ("SGC", "10"):
            return true
        default:
            return false
        }
    }

    private func caveatRow(_ message: String) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: (pptSnapshot?.isStaleFallback ?? false) ? "wifi.slash" : "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle((pptSnapshot?.isStaleFallback ?? false) ? AppColor.negative : AppColor.dim)
            Text(message)
                .font(SlabFont.sans(size: 12, weight: .medium))
                .foregroundStyle((pptSnapshot?.isStaleFallback ?? false) ? AppColor.negative : AppColor.dim)
            Spacer()
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerRow: some View {
        if let url = pptSnapshot?.pptURL {
            Link(destination: url) {
                HStack(spacing: Spacing.xxs) {
                    Text("Powered by Pokemon Price Tracker · View card")
                        .font(SlabFont.sans(size: 12, weight: .medium))
                        .foregroundStyle(AppColor.gold)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColor.gold)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack {
                Text("Comp data from Pokemon Price Tracker + Poketrace")
                    .font(SlabFont.sans(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.dim)
                Spacer()
            }
        }
    }

    // MARK: - Formatters

    fileprivate static func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        fmt.maximumFractionDigits = 2
        return fmt.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }

    fileprivate static func formatCentsCompact(_ cents: Int64) -> String {
        let dollars = Int((Double(cents) / 100).rounded())
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        fmt.maximumFractionDigits = 0
        return fmt.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }

    private func formatCents(_ cents: Int64) -> String { Self.formatCents(cents) }
    private func formatCentsCompact(_ cents: Int64) -> String { Self.formatCentsCompact(cents) }
}

// MARK: - Source price cell

/// One column of the side-by-side sources strip. Renders gracefully
/// when the source has no data (`—` + "no data" in dim).
private struct SourcePriceCell: View {
    let title: String
    let priceCents: Int64?
    let accessoryLine1: String?
    let accessoryLine2: String?
    /// Poketrace-only "high" / "medium" / "low". Tints the price text.
    let confidence: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(SlabFont.sans(size: 10, weight: .medium))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.dim)
            if let cents = priceCents {
                Text(CompCardView.formatCents(cents))
                    .font(SlabFont.mono(size: 18, weight: .semibold))
                    .foregroundStyle(priceColor)
            } else {
                Text("—")
                    .font(SlabFont.mono(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.dim)
                Text("no data")
                    .font(SlabFont.sans(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.dim)
            }
            if let l1 = accessoryLine1 {
                Text(l1)
                    .font(SlabFont.mono(size: 11, weight: .regular))
                    .foregroundStyle(AppColor.muted)
            }
            if let l2 = accessoryLine2 {
                Text(l2)
                    .font(SlabFont.sans(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Confidence-based price tint. We never grey out below `muted` —
    /// this is a working tool, the price still has to read first.
    private var priceColor: Color {
        switch confidence {
        case "high":   return AppColor.text
        case "medium": return AppColor.text.opacity(0.85)
        case "low":    return AppColor.muted
        default:       return AppColor.text
        }
    }
}

// MARK: - Previews

#Preview("Both sources · PSA 10") {
    let history: [PriceHistoryPoint] = (0..<10).map { i in
        let interval: TimeInterval = TimeInterval(-i * 86_400 * 18)
        let price: Int64 = Int64(18_500 - i * 200)
        return PriceHistoryPoint(ts: Date(timeIntervalSinceNow: interval), priceCents: price)
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let json = String(data: (try? encoder.encode(history)) ?? Data(), encoding: .utf8)
    let identityId = UUID()
    let scan = Scan(
        id: UUID(), storeId: UUID(), lotId: UUID(), userId: UUID(),
        grader: .PSA, certNumber: "12345678",
        grade: "10",
        gradedCardIdentityId: identityId,
        status: .validated,
        createdAt: Date(), updatedAt: Date()
    )
    scan.reconciledHeadlinePriceCents = 18_750
    let ppt = GradedMarketSnapshot(
        identityId: identityId, gradingService: "PSA", grade: "10",
        source: GradedMarketSnapshot.sourcePPT,
        headlinePriceCents: 18500, loosePriceCents: 400,
        psa7PriceCents: 2400, psa8PriceCents: 3400, psa9PriceCents: 6800,
        psa9_5PriceCents: 11200, psa10PriceCents: 18500,
        bgs10PriceCents: 21500, cgc10PriceCents: 16800, sgc10PriceCents: 16500,
        pptTCGPlayerId: "243172",
        pptURL: URL(string: "https://www.pokemonpricetracker.com/card/charizard-base-set"),
        priceHistoryJSON: json,
        fetchedAt: Date(), cacheHit: false, isStaleFallback: false
    )
    let pt = GradedMarketSnapshot(
        identityId: identityId, gradingService: "PSA", grade: "10",
        source: GradedMarketSnapshot.sourcePoketrace,
        headlinePriceCents: 19_000,
        ptAvgCents: 19_000, ptLowCents: 17_500, ptHighCents: 21_000,
        ptTrend: "up", ptConfidence: "high", ptSaleCount: 14,
        priceHistoryJSON: json,
        fetchedAt: Date(), cacheHit: false, isStaleFallback: false
    )
    return CompCardView(scan: scan, pptSnapshot: ppt, poketraceSnapshot: pt)
        .padding().background(Color.black)
}

#Preview("PPT only · BGS 10") {
    let identityId = UUID()
    let scan = Scan(
        id: UUID(), storeId: UUID(), lotId: UUID(), userId: UUID(),
        grader: .BGS, certNumber: "98765432",
        grade: "10",
        gradedCardIdentityId: identityId,
        status: .validated,
        createdAt: Date(), updatedAt: Date()
    )
    scan.reconciledHeadlinePriceCents = 21_500
    let ppt = GradedMarketSnapshot(
        identityId: identityId, gradingService: "BGS", grade: "10",
        source: GradedMarketSnapshot.sourcePPT,
        headlinePriceCents: 21500, loosePriceCents: 400,
        psa7PriceCents: nil, psa8PriceCents: nil, psa9PriceCents: nil,
        psa9_5PriceCents: nil, psa10PriceCents: 18500,
        bgs10PriceCents: 21500, cgc10PriceCents: 16800, sgc10PriceCents: nil,
        pptTCGPlayerId: "243172",
        pptURL: URL(string: "https://www.pokemonpricetracker.com/card/charizard-base-set"),
        priceHistoryJSON: nil,
        fetchedAt: Date(), cacheHit: false, isStaleFallback: false
    )
    return CompCardView(scan: scan, pptSnapshot: ppt, poketraceSnapshot: nil)
        .padding().background(Color.black)
}

#Preview("Poketrace only · PSA 9") {
    let identityId = UUID()
    let scan = Scan(
        id: UUID(), storeId: UUID(), lotId: UUID(), userId: UUID(),
        grader: .PSA, certNumber: "55555555",
        grade: "9",
        gradedCardIdentityId: identityId,
        status: .validated,
        createdAt: Date(), updatedAt: Date()
    )
    scan.reconciledHeadlinePriceCents = 6_800
    let pt = GradedMarketSnapshot(
        identityId: identityId, gradingService: "PSA", grade: "9",
        source: GradedMarketSnapshot.sourcePoketrace,
        headlinePriceCents: 6_800,
        ptAvgCents: 6_800, ptLowCents: 6_100, ptHighCents: 7_400,
        ptTrend: "stable", ptConfidence: "medium", ptSaleCount: 6,
        priceHistoryJSON: nil,
        fetchedAt: Date(), cacheHit: false, isStaleFallback: false
    )
    return CompCardView(scan: scan, pptSnapshot: nil, poketraceSnapshot: pt)
        .padding().background(Color.black)
}
