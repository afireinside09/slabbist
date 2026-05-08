import XCTest

/// Wraps `XCUIApplication.performAccessibilityAudit()` (iOS 17+) so every
/// XCUITest can drop a one-liner audit at any point in a flow. The audit
/// surfaces missing labels, low contrast, undersized hit targets, dynamic-
/// type clipping, hidden traits, and other accessibility regressions —
/// exactly the class of UX bugs that survive snapshot diffs but break for
/// real users.
///
/// Tests should call this at every stable navigation point, e.g.:
///
///     let app = UITestApp.launch()
///     try app.auditA11y(named: "Lots tab")
///     app.buttons["new-lot-button"].tap()
///     try app.auditA11y(named: "New lot sheet")
///
/// On failure, every issue is printed (with element + category) before
/// the test fails so the report points at the broken UI, not just
/// "audit failed".
extension XCUIApplication {
    /// Run the system accessibility audit at the current screen state.
    ///
    /// `name` is a human-readable label used in the failure message —
    /// pick something a teammate can find quickly in the test output
    /// (e.g. "lots tab", "new lot sheet").
    ///
    /// `audit` selects which audit categories to run. Defaults to
    /// `.defaultStableSet`, which is `.all` minus contrast and clipping
    /// — those two need design review (color tokens, font sizing) so
    /// they tend to flag *real findings* on existing screens. Pass
    /// `.all` (or `.contrast` directly) when you're ready to graduate.
    ///
    /// `ignoring` lets a test skip individual elements (by identifier
    /// or label fragment) when an exception is genuinely warranted.
    /// Prefer fixing the UI; use this only when the issue is a known
    /// false positive (e.g. third-party SDK chrome).
    func auditA11y(
        named name: String,
        audit: XCUIAccessibilityAuditType = .defaultStableSet,
        ignoring ignoreList: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var captured: [String] = []
        do {
            try performAccessibilityAudit(for: audit) { [self] issue in
                let summary = self.describe(issue: issue)
                if Self.shouldIgnore(issue: issue, ignoreList: ignoreList) {
                    return true // ignore
                }
                captured.append(summary)
                return false
            }
        } catch {
            // performAccessibilityAudit only throws when the handler
            // returned `false` for at least one issue. The handler has
            // already accumulated the descriptive lines.
            let detail = captured.joined(separator: "\n  • ")
            XCTFail(
                """
                Accessibility audit failed at '\(name)':
                  • \(detail.isEmpty ? error.localizedDescription : detail)
                """,
                file: file,
                line: line
            )
            throw error
        }
    }

    private func describe(issue: XCUIAccessibilityAuditIssue) -> String {
        let category = String(describing: issue.auditType)
        let elementId = issue.element?.identifier
        let elementLabel = issue.element?.label
        let detail = issue.compactDescription
        let identityHint: String
        if let elementId, !elementId.isEmpty {
            identityHint = "id=\(elementId)"
        } else if let elementLabel, !elementLabel.isEmpty {
            identityHint = "label='\(elementLabel)'"
        } else {
            identityHint = "<unidentified element>"
        }
        return "[\(category)] \(identityHint) — \(detail)"
    }

    private static func shouldIgnore(
        issue: XCUIAccessibilityAuditIssue,
        ignoreList: [String]
    ) -> Bool {
        guard !ignoreList.isEmpty else { return false }
        let id = issue.element?.identifier ?? ""
        let label = issue.element?.label ?? ""
        return ignoreList.contains { needle in
            id.contains(needle) || label.contains(needle)
        }
    }
}

extension XCUIAccessibilityAuditType {
    /// Categories that have been most useful here without flagging
    /// known design-system tradeoffs. Specifically excludes:
    ///
    ///   * `.contrast` — the dark+gold palette uses `AppColor.dim`
    ///     (alpha 0.36) which falls below the WCAG AA threshold by
    ///     design. Token-level remediation is its own design-system
    ///     review; tracked separately.
    ///   * `.dynamicType` — typography uses fixed sizes via
    ///     `SlabFont.sans(size:)` rather than `.relativeTo:`. Migrating
    ///     to relative sizing is a typography refactor, not a per-view
    ///     fix.
    ///   * `.textClipped` — overlapping with `.dynamicType`; tends to
    ///     false-positive on `.lineLimit(1) + .truncationMode(.tail)`
    ///     rows that intentionally truncate long card titles.
    ///
    /// Everything else stays on by default — those are the categories
    /// that catch actionable regressions on the current design without
    /// needing a token-level rewrite. Tests that want strict coverage
    /// can still pass `.all` explicitly.
    static var defaultStableSet: XCUIAccessibilityAuditType {
        let exclusions: XCUIAccessibilityAuditType = [
            .contrast,
            .dynamicType,
            .textClipped
        ]
        return XCUIAccessibilityAuditType(
            rawValue: XCUIAccessibilityAuditType.all.rawValue & ~exclusions.rawValue
        )
    }
}
