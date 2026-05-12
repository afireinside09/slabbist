# Lot Flow UX Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce friction in the lot → offer flow: combined margin sheet, one-tap offer creation with auto-navigation, auto-dismiss on Bounce Back, and clearly styled secondary action buttons.

**Architecture:** New `SecondaryButtonStyle` component; new `LotMarginSheet` that merges `MarginPickerSheet` + `MarginLadderView`; thread `$path` binding into `LotDetailView` so "Create Offer" can push `OfferReviewView` directly; `dismiss()` added to `bounceBack()` handler in `OfferReviewView`. UI tests updated to reflect new navigation flow.

**Tech Stack:** SwiftUI, SwiftData, XCTest / Swift Testing, xcodebuild

---

## File Map

| File | Action |
|------|--------|
| `ios/slabbist/slabbist/Core/DesignSystem/Components/SecondaryButton.swift` | **Create** — `SecondaryButtonStyle` + `SecondaryButton` |
| `ios/slabbist/slabbist/Features/Offers/LotMarginSheet.swift` | **Create** — combined lot override + store ladder sheet |
| `ios/slabbist/slabbist/Features/Lots/LotDetailView.swift` | **Modify** — add `$path` binding, swap sheet, rename + auto-nav CTA, restyle Resume Offer |
| `ios/slabbist/slabbist/Features/Lots/LotsListView.swift` | **Modify** — pass `$path` when constructing `LotDetailView` |
| `ios/slabbist/slabbist/Features/Offers/OfferReviewView.swift` | **Modify** — `dismiss()` on bounce-back, restyle secondary actions |
| `ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift` | **Modify** — add `SecondaryButton` render test |
| `ios/slabbist/slabbistUITests/OfferPricingFlowUITests.swift` | **Modify** — update for new navigation flow |
| `ios/slabbist/slabbistUITests/TransactionFlowUITests.swift` | **Modify** — update for new navigation flow |

---

## Task 1: SecondaryButtonStyle + SecondaryButton

**Files:**
- Create: `ios/slabbist/slabbist/Core/DesignSystem/Components/SecondaryButton.swift`
- Modify: `ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift`

- [ ] **Step 1.1: Add failing smoke test**

Open `ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift` and add after the `secondaryIconButtonRenders` test:

```swift
@Test("SecondaryButton renders")
func secondaryButtonRenders() {
    let host = UIHostingController(
        rootView: SecondaryButton(title: "Resume offer", action: {})
    )
    #expect(host.view != nil)
}

@Test("SecondaryButton destructive renders")
func secondaryButtonDestructiveRenders() {
    let host = UIHostingController(
        rootView: SecondaryButton(title: "Decline", role: .destructive, action: {})
    )
    #expect(host.view != nil)
}
```

- [ ] **Step 1.2: Run to confirm failure**

```bash
xcodebuild test \
  -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:slabbistTests/PrimitiveSmokeTests/secondaryButtonRenders \
  2>&1 | grep -E "error:|FAILED|passed"
```

Expected: build error — `SecondaryButton` is not defined.

- [ ] **Step 1.3: Create `SecondaryButton.swift`**

Create `ios/slabbist/slabbist/Core/DesignSystem/Components/SecondaryButton.swift`:

```swift
import SwiftUI

struct SecondaryButtonStyle: ButtonStyle {
    enum Role { case standard, destructive }
    var role: Role = .standard

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SlabFont.sans(size: 15, weight: .semibold))
            .foregroundStyle(role == .destructive ? AppColor.negative : AppColor.muted)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .stroke(
                        role == .destructive ? AppColor.negative : AppColor.muted,
                        lineWidth: 1
                    )
            )
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

struct SecondaryButton: View {
    let title: String
    var role: SecondaryButtonStyle.Role = .standard
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(SecondaryButtonStyle(role: role))
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1.0 : 0.4)
    }
}

#Preview("SecondaryButton") {
    VStack(spacing: Spacing.l) {
        SecondaryButton(title: "Resume offer", action: {})
        SecondaryButton(title: "Bounce back", action: {})
        SecondaryButton(title: "Decline", role: .destructive, action: {})
        SecondaryButton(title: "Disabled", isEnabled: false, action: {})
    }
    .padding()
    .background(AppColor.ink)
}
```

- [ ] **Step 1.4: Run smoke tests**

```bash
xcodebuild test \
  -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:slabbistTests/PrimitiveSmokeTests \
  2>&1 | grep -E "error:|Test.*passed|Test.*failed"
```

Expected: all `PrimitiveSmokeTests` pass including the two new ones.

- [ ] **Step 1.5: Commit**

```bash
git add \
  ios/slabbist/slabbist/Core/DesignSystem/Components/SecondaryButton.swift \
  ios/slabbist/slabbistTests/Core/DesignSystem/PrimitiveSmokeTests.swift
git commit -m "feat(ios): SecondaryButtonStyle + SecondaryButton design system component"
```

---

## Task 2: LotMarginSheet

**Files:**
- Create: `ios/slabbist/slabbist/Features/Offers/LotMarginSheet.swift`

- [ ] **Step 2.1: Create `LotMarginSheet.swift`**

Create `ios/slabbist/slabbist/Features/Offers/LotMarginSheet.swift`:

```swift
import SwiftUI
import SwiftData

/// Combined sheet for adjusting a lot's margin override and editing the
/// store-wide margin ladder. Replaces `MarginPickerSheet` as the target
/// of the "Adjust" button in `LotDetailView`.
///
/// The lot override and the store ladder save independently — lot override
/// dismisses the sheet; ladder save stays open for further edits.
struct LotMarginSheet: View {
    let currentPct: Double
    let storeId: UUID
    let onSelectLotMargin: (Double) -> Void

    @Environment(\.modelContext) private var context
    @Environment(OutboxKicker.self) private var kicker
    @Environment(\.dismiss) private var dismiss

    @State private var pct: Double
    @State private var tiers: [Row] = []
    @State private var initialTiers: [MarginTier] = []
    @State private var ladderError: String?

    private static let snaps: [Double] = [0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00]

    init(currentPct: Double, storeId: UUID, onSelectLotMargin: @escaping (Double) -> Void) {
        self.currentPct = currentPct
        self.storeId = storeId
        self.onSelectLotMargin = onSelectLotMargin
        _pct = State(initialValue: currentPct)
    }

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    lotSection
                    ladderSection
                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.vertical, Spacing.l)
            }
        }
        .task { loadLadder() }
    }

    // MARK: - Lot override section

    private var lotSection: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            KickerLabel("Lot margin override")
            Text("\(Int((pct * 100).rounded()))% of comp").slabTitle()
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 56), spacing: Spacing.s)],
                alignment: .leading,
                spacing: Spacing.s
            ) {
                ForEach(Self.snaps, id: \.self) { snap in
                    Button("\(Int(snap * 100))%") { pct = snap }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.s)
                        .background(snap == pct ? AppColor.gold.opacity(0.2) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColor.gold, lineWidth: snap == pct ? 1.5 : 0.5)
                        )
                        .accessibilityIdentifier("margin-snap-\(Int(snap * 100))")
                }
            }
            Slider(value: $pct, in: 0.70...1.00, step: 0.01)
                .accessibilityIdentifier("margin-slider")
            PrimaryGoldButton(title: "Save lot margin") {
                onSelectLotMargin(pct)
                dismiss()
            }
            .accessibilityIdentifier("margin-save")
        }
    }

    // MARK: - Store ladder section

    private var ladderSection: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            KickerLabel("Margin ladder")
            Text("Changes apply to all future auto-priced lots.")
                .font(SlabFont.sans(size: 13))
                .foregroundStyle(AppColor.muted)
            SlabCard {
                VStack(spacing: 0) {
                    ForEach(tiers) { row in
                        if row.id != tiers.first?.id { SlabCardDivider() }
                        tierRow(row)
                    }
                    SlabCardDivider()
                    Button {
                        let nextCents: Int64 = (tiers.map(\.cents).max() ?? 0) + 50_000
                        tiers.insert(Row(id: UUID(), cents: nextCents, pct: 0.80), at: 0)
                        ladderError = nil
                    } label: {
                        HStack(spacing: Spacing.s) {
                            Image(systemName: "plus")
                                .font(SlabFont.sans(size: 13, weight: .semibold))
                            Text("Add tier")
                                .font(SlabFont.sans(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(AppColor.gold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("margin-ladder-add")
                }
            }
            if let ladderError {
                Text(ladderError)
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.negative)
                    .accessibilityIdentifier("margin-ladder-error")
            }
            PrimaryGoldButton(title: "Save ladder", isEnabled: hasLadderChanges) {
                saveLadder()
            }
            .accessibilityIdentifier("margin-ladder-save")
            Button("Reset to defaults") {
                tiers = Self.makeRows(from: .defaultMarginLadder)
                ladderError = nil
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.muted)
            .accessibilityIdentifier("margin-ladder-reset")
        }
    }

    @ViewBuilder
    private func tierRow(_ row: Row) -> some View {
        let binding = Binding<Row>(
            get: { tiers.first(where: { $0.id == row.id }) ?? row },
            set: { new in
                if let idx = tiers.firstIndex(where: { $0.id == new.id }) {
                    tiers[idx] = new
                }
            }
        )
        HStack(alignment: .center, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                KickerLabel("If comp ≥")
                HStack(spacing: Spacing.xs) {
                    Text("$")
                        .font(SlabFont.mono(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.dim)
                    TextField("0", text: binding.dollarsText)
                        .keyboardType(.numberPad)
                        .font(SlabFont.mono(size: 14, weight: .semibold))
                        .frame(minWidth: 60)
                        .accessibilityIdentifier("margin-ladder-cents-\(row.id)")
                }
            }
            Spacer(minLength: Spacing.m)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                KickerLabel("Pay")
                HStack(spacing: Spacing.xs) {
                    TextField("70", text: binding.percentText)
                        .keyboardType(.numberPad)
                        .font(SlabFont.mono(size: 14, weight: .semibold))
                        .frame(minWidth: 44)
                        .accessibilityIdentifier("margin-ladder-pct-\(row.id)")
                    Text("%")
                        .font(SlabFont.mono(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.dim)
                }
            }
            Button {
                tiers.removeAll { $0.id == row.id }
                ladderError = nil
            } label: {
                Image(systemName: "minus.circle")
                    .font(SlabFont.sans(size: 16, weight: .regular))
                    .foregroundStyle(AppColor.dim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tier")
            .accessibilityIdentifier("margin-ladder-remove-\(row.id)")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Ladder data

    private var hasLadderChanges: Bool {
        tiers.compactMap(\.materialized).canonicalized() != initialTiers
    }

    private func loadLadder() {
        var descriptor = FetchDescriptor<Store>(predicate: #Predicate { $0.id == storeId })
        descriptor.fetchLimit = 1
        guard let store = try? context.fetch(descriptor).first else { return }
        let canonical = store.marginLadder.canonicalized()
        initialTiers = canonical
        tiers = Self.makeRows(from: canonical)
    }

    private func saveLadder() {
        let materialized = tiers.compactMap(\.materialized)
        guard materialized.count == tiers.count else {
            ladderError = "Each tier needs a comp threshold and a margin between 1–100%."
            return
        }
        guard !materialized.isEmpty else {
            ladderError = "Add at least one tier."
            return
        }
        let repo = StoreSettingsRepository(context: context, kicker: kicker, currentStoreId: storeId)
        do {
            try repo.updateMarginLadder(materialized)
            initialTiers = materialized.canonicalized()
            ladderError = nil
        } catch {
            ladderError = error.localizedDescription
        }
    }

    private static func makeRows(from tiers: [MarginTier]) -> [Row] {
        tiers.canonicalized().map { Row(id: UUID(), cents: $0.minCompCents, pct: $0.marginPct) }
    }

    // MARK: - Row model (mirrors MarginLadderView.Row, kept private to this file)

    fileprivate struct Row: Identifiable, Equatable {
        let id: UUID
        var cents: Int64
        var pct: Double

        var materialized: MarginTier? {
            guard cents >= 0, pct > 0, pct <= 1 else { return nil }
            return MarginTier(minCompCents: cents, marginPct: pct)
        }
    }
}

// MARK: - Bindings (mirrors MarginLadderView binding extensions)

private extension Binding where Value == LotMarginSheet.Row {
    var dollarsText: Binding<String> {
        Binding<String>(
            get: { String(wrappedValue.cents / 100) },
            set: { new in
                let digits = new.filter(\.isNumber)
                wrappedValue.cents = (Int64(digits) ?? 0) * 100
            }
        )
    }

    var percentText: Binding<String> {
        Binding<String>(
            get: { String(Int((wrappedValue.pct * 100).rounded())) },
            set: { new in
                let digits = new.filter(\.isNumber)
                guard let pct = Int(digits) else { wrappedValue.pct = 0; return }
                let clamped = Swift.min(Swift.max(pct, 0), 100)
                wrappedValue.pct = Double(clamped) / 100.0
            }
        )
    }
}
```

- [ ] **Step 2.2: Build to confirm no errors**

```bash
xcodebuild build \
  -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`

- [ ] **Step 2.3: Commit**

```bash
git add ios/slabbist/slabbist/Features/Offers/LotMarginSheet.swift
git commit -m "feat(ios): LotMarginSheet — combined lot override + store ladder editor"
```

---

## Task 3: LotDetailView + LotsListView wiring

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Lots/LotDetailView.swift`
- Modify: `ios/slabbist/slabbist/Features/Lots/LotsListView.swift`

- [ ] **Step 3.1: Add `@Binding var path: [LotsRoute]` to LotDetailView**

In `LotDetailView.swift`, add the binding property after the existing `@State` declarations (around line 19):

```swift
@Binding var path: [LotsRoute]
```

Update the `init` to accept it (the `init` currently starts at line 21):

```swift
init(lot: Lot, path: Binding<[LotsRoute]>) {
    self.lot = lot
    self._path = path
    let lotId = lot.id
    _scans = Query(
        filter: #Predicate<Scan> { $0.lotId == lotId },
        sort: [SortDescriptor(\Scan.createdAt, order: .reverse)]
    )
    _snapshots = Query(sort: [SortDescriptor(\GradedMarketSnapshot.fetchedAt, order: .reverse)])
    _identities = Query()
}
```

- [ ] **Step 3.2: Swap MarginPickerSheet for LotMarginSheet**

Find the `.sheet(isPresented: $showingMarginSheet)` modifier in `LotDetailView.body` (around line 75) and replace it:

```swift
.sheet(isPresented: $showingMarginSheet) {
    LotMarginSheet(
        currentPct: lot.marginPctSnapshot ?? 0.7,
        storeId: lot.storeId,
        onSelectLotMargin: { pct in
            try? offerRepository().setLotMargin(pct, on: lot)
        }
    )
}
```

- [ ] **Step 3.3: Rename CTA and add auto-navigation**

In `actionBar`, find the `.priced` case (around line 290):

```swift
case .priced:
    PrimaryGoldButton(title: "Send to offer") {
        try? offerRepository().sendToOffer(lot)
    }
    .accessibilityIdentifier("send-to-offer")
```

Replace with:

```swift
case .priced:
    PrimaryGoldButton(title: "Create Offer") {
        try? offerRepository().sendToOffer(lot)
        path.append(LotsRoute.offerReview(lot.id))
    }
    .accessibilityIdentifier("create-offer")
```

- [ ] **Step 3.4: Style "Resume offer" as SecondaryButton**

In `actionBar`, find the `.presented, .accepted` case (around line 295):

```swift
case .presented, .accepted:
    NavigationLink("Resume offer", value: LotsRoute.offerReview(lot.id))
        .accessibilityIdentifier("resume-offer")
```

Replace with:

```swift
case .presented, .accepted:
    NavigationLink(value: LotsRoute.offerReview(lot.id)) {
        Text("Resume offer")
    }
    .buttonStyle(SecondaryButtonStyle())
    .accessibilityIdentifier("resume-offer")
```

- [ ] **Step 3.5: Pass `$path` in LotsListView**

In `LotsListView.swift`, find the `.lot(let lotId)` case inside `routeDestination` (around line 293):

```swift
case .lot(let lotId):
    if let lot = try? context.fetch(
        FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })
    ).first {
        LotDetailView(lot: lot)
    } else {
        missingEntityView(label: "Lot")
    }
```

Replace with:

```swift
case .lot(let lotId):
    if let lot = try? context.fetch(
        FetchDescriptor<Lot>(predicate: #Predicate { $0.id == lotId })
    ).first {
        LotDetailView(lot: lot, path: $path)
    } else {
        missingEntityView(label: "Lot")
    }
```

- [ ] **Step 3.6: Build to confirm no errors**

```bash
xcodebuild build \
  -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`

- [ ] **Step 3.7: Commit**

```bash
git add \
  ios/slabbist/slabbist/Features/Lots/LotDetailView.swift \
  ios/slabbist/slabbist/Features/Lots/LotsListView.swift
git commit -m "feat(ios): Create Offer auto-nav + LotMarginSheet + SecondaryButtonStyle on Resume Offer"
```

---

## Task 4: OfferReviewView — Bounce Back dismiss + button hierarchy

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Offers/OfferReviewView.swift`

- [ ] **Step 4.1: Update `actionStack`**

In `OfferReviewView.swift`, find `private var actionStack: some View` (around line 132) and replace the entire computed property:

```swift
private var actionStack: some View {
    VStack(spacing: Spacing.m) {
        PrimaryGoldButton(
            title: isCommitting ? "Committing…" : "Mark paid",
            isEnabled: canMarkPaid && !isCommitting
        ) {
            commit()
        }
        .accessibilityIdentifier("mark-paid")

        if let commitError {
            Text(commitError)
                .font(SlabFont.sans(size: 13))
                .foregroundStyle(AppColor.negative)
                .accessibilityIdentifier("offer-review-commit-error")
        }

        if isCommitting && LotOfferState(rawValue: lot.lotOfferState) != .paid {
            Text("Sync pending — your offer is saved. Receipt will appear once we reach the server.")
                .font(SlabFont.sans(size: 12)).foregroundStyle(AppColor.muted)
                .accessibilityIdentifier("offer-review-sync-pending")
        }

        Button("Bounce back") {
            do {
                try offerRepository().bounceBack(lot)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("bounce-back")

        Button("Decline") {
            do { try offerRepository().decline(lot) }
            catch { self.error = error.localizedDescription }
        }
        .buttonStyle(SecondaryButtonStyle(role: .destructive))
        .accessibilityIdentifier("decline-offer")
    }
}
```

- [ ] **Step 4.2: Build to confirm no errors**

```bash
xcodebuild build \
  -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`

- [ ] **Step 4.3: Commit**

```bash
git add ios/slabbist/slabbist/Features/Offers/OfferReviewView.swift
git commit -m "feat(ios): Bounce Back auto-dismiss + SecondaryButtonStyle on Decline"
```

---

## Task 5: Update UI tests for new navigation flow

The tests that tap "send-to-offer" then "resume-offer" break because "Create Offer" now auto-navigates directly to `OfferReviewView`. The tests that manually pop after "bounce-back" break because `dismiss()` now handles that automatically.

**Files:**
- Modify: `ios/slabbist/slabbistUITests/OfferPricingFlowUITests.swift`
- Modify: `ios/slabbist/slabbistUITests/TransactionFlowUITests.swift`

- [ ] **Step 5.1: Update OfferPricingFlowUITests**

In `OfferPricingFlowUITests.swift`, replace the entire `test_price_send_bounce_decline_flow` method body with:

```swift
@MainActor
func test_price_send_bounce_decline_flow() throws {
    let app = UITestApp.launch([.seedPricedLot])

    // 1. Lots tab is the default tab; the seeded lot is already on it.
    let lotRow = app.buttons["lot-row-Sample Lot"]
    XCTAssertTrue(
        lotRow.waitForExistence(timeout: 5),
        "Seeded Sample Lot should appear on the Lots list"
    )
    app.staticTexts["Sample Lot"].tap()

    // 2. Adjust margin to 70% via LotMarginSheet.
    let adjustMargin = app.buttons["lot-margin-adjust"]
    XCTAssertTrue(
        adjustMargin.waitForExistence(timeout: 3),
        "Adjust margin affordance should render on a priced lot"
    )
    adjustMargin.tap()

    let snap70 = app.buttons["margin-snap-70"]
    XCTAssertTrue(snap70.waitForExistence(timeout: 2))
    snap70.tap()
    app.buttons["margin-save"].tap()

    // 3. Open the seeded scan and override its buy price.
    let scanRow = app.buttons["scan-row-55667788"]
    XCTAssertTrue(
        scanRow.waitForExistence(timeout: 3),
        "Seeded scan row should appear on lot detail"
    )
    scanRow.tap()

    // 4. Tap "Edit" on the buy-price card.
    let editBuy = app.buttons["buy-price-edit"]
    XCTAssertTrue(editBuy.waitForExistence(timeout: 3))
    editBuy.tap()

    // 5. Override the buy price.
    let field = app.textFields["buy-price-field"]
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    field.tap()
    field.doubleTap()
    if let value = field.value as? String, !value.isEmpty {
        let backspace = String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)
        field.typeText(backspace)
    }
    field.typeText("75.00")

    let save = app.buttons["buy-price-save"]
    XCTAssertTrue(save.waitForExistence(timeout: 2))
    XCTAssertTrue(save.isEnabled)
    save.tap()

    XCTAssertTrue(
        app.buttons["buy-price-reset"].waitForExistence(timeout: 3),
        "Reset-to-auto affordance should appear after overriding the buy price"
    )

    // 6. Pop back to LotDetailView and tap Create Offer.
    let backButton = app.navigationBars.buttons.element(boundBy: 0)
    XCTAssertTrue(backButton.waitForExistence(timeout: 2))
    backButton.tap()

    let createOffer = app.buttons["create-offer"]
    XCTAssertTrue(
        createOffer.waitForExistence(timeout: 3),
        "Create Offer CTA should render on a priced lot"
    )
    createOffer.tap()

    // 7. Create Offer auto-navigates — OfferReviewView renders immediately.
    XCTAssertTrue(
        app.staticTexts["Offer total"].waitForExistence(timeout: 3),
        "OfferReviewView should render immediately after tapping Create Offer"
    )

    // 8. Bounce back — auto-dismisses to LotDetailView.
    let bounceBack = app.buttons["bounce-back"]
    XCTAssertTrue(bounceBack.waitForExistence(timeout: 2))
    bounceBack.tap()

    XCTAssertTrue(
        app.buttons["create-offer"].waitForExistence(timeout: 3),
        "Bouncing back should auto-dismiss to lot detail with Create Offer CTA"
    )

    // 9. Send again — already lands on OfferReviewView.
    app.buttons["create-offer"].tap()
    XCTAssertTrue(app.staticTexts["Offer total"].waitForExistence(timeout: 3))

    // 10. Decline — stays on OfferReviewView; pop back to confirm lot state.
    let decline = app.buttons["decline-offer"]
    XCTAssertTrue(decline.waitForExistence(timeout: 2))
    decline.tap()

    let backAfterDecline = app.navigationBars.buttons.element(boundBy: 0)
    if backAfterDecline.exists { backAfterDecline.tap() }
    XCTAssertTrue(
        app.buttons["reopen-declined"].waitForExistence(timeout: 3),
        "Declined lot should expose the re-open affordance"
    )
}
```

- [ ] **Step 5.2: Update TransactionFlowUITests**

In `TransactionFlowUITests.swift`, find the block that taps "send-to-offer" then "resume-offer" (around lines 40–54) and replace it:

```swift
// Lot is in .priced — Create Offer is the only legal CTA.
let createOffer = app.buttons["create-offer"]
XCTAssertTrue(
    createOffer.waitForExistence(timeout: 3),
    "Create Offer CTA should render on a priced lot"
)
createOffer.tap()

// Create Offer auto-navigates — OfferReviewView renders immediately.
```

The lines after this (starting with `let markPaid = app.buttons["mark-paid"]`) are unchanged.

- [ ] **Step 5.3: Run the unit test suite to confirm no regressions**

```bash
xcodebuild test \
  -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:slabbistTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|error:"
```

Expected: all unit tests pass.

- [ ] **Step 5.4: Run the UI test suite**

```bash
xcodebuild test \
  -project ios/slabbist/slabbist.xcodeproj \
  -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:slabbistUITests \
  2>&1 | grep -E "Test.*passed|Test.*failed|error:"
```

Expected: `OfferPricingFlowUITests` and `TransactionFlowUITests` pass with the updated flows.

- [ ] **Step 5.5: Commit**

```bash
git add \
  ios/slabbist/slabbistUITests/OfferPricingFlowUITests.swift \
  ios/slabbist/slabbistUITests/TransactionFlowUITests.swift
git commit -m "test(ios): update UI tests for Create Offer auto-nav + Bounce Back auto-dismiss"
```

---

## Verification Checklist

1. Tap "Adjust" on a lot's margin row → sheet shows snap buttons + slider at top, store tier editor below. "Save lot margin" dismisses sheet. "Save ladder" saves tiers and stays open; verify by re-opening sheet and seeing the new tiers.
2. Tap "Create Offer" on a `.priced` lot → OfferReviewView opens immediately (no intermediate "Resume offer" tap required).
3. From OfferReviewView, tap "Bounce back" → view dismisses and lands on LotDetailView showing "Create Offer".
4. "Resume offer" renders as a bordered outline button (not a plain link). "Bounce back" and "Decline" render as full-width bordered buttons below "Mark paid".
5. "Bounce back" and "Resume offer" use muted borders; "Decline" uses a red/negative border.
6. All unit tests pass: `xcodebuild test -only-testing:slabbistTests`
7. All UI tests pass: `xcodebuild test -only-testing:slabbistUITests`
