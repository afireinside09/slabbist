import XCTest

/// Wraps `XCUIApplication.performAccessibilityAudit()` (iOS 17+) so every
/// XCUITest can drop a one-liner audit at any point in a flow. The audit
/// surfaces missing labels, low contrast, undersized hit targets, dynamic-
/// type clipping, hidden traits, and other accessibility regressions —
/// exactly the class of UX bugs that survive snapshot diffs but break for
/// real users.
///
/// The default mode is **report-only**: issues are attached to the test
/// report and printed to stderr, but the test continues. Tests opt into
/// `strict: true` when a screen has been remediated and we want the audit
/// to gate that screen against future regressions.
///
/// ```swift
/// let app = UITestApp.launch()
/// // Lots-empty has been reviewed → enforce strictly.
/// try app.auditA11y(named: "lots tab (empty)", strict: true)
/// app.buttons["new-lot-button"].tap()
/// // New-lot sheet hasn't been reviewed yet → report-only.
/// try app.auditA11y(named: "new lot sheet")
/// ```
extension XCUIApplication {
    /// Run the system accessibility audit at the current screen state.
    ///
    /// `name` is a human-readable label used in the failure / report
    /// message — pick something a teammate can find quickly in the test
    /// output (e.g. "lots tab", "new lot sheet").
    ///
    /// `audit` selects which audit categories to run. Defaults to
    /// `.defaultStableSet`, which is `.all` minus contrast / dynamicType
    /// / textClipped — those need design-system review (color tokens,
    /// font sizing) so they tend to flag *real findings* on existing
    /// screens. Pass `.all` (or `.contrast` directly) when you're ready
    /// to graduate.
    ///
    /// `strict` controls whether issues fail the test. Defaults to
    /// `false` — issues are still attached to the test report so the
    /// engineer can see what was flagged, but the test continues. Pass
    /// `strict: true` for screens that have been audited and should
    /// stay clean.
    ///
    /// `ignoring` lets a test skip individual elements (by identifier
    /// or label fragment). Prefer fixing the UI; use this only when the
    /// issue is a known false positive (e.g. SwiftUI Menu's wrapper
    /// button surfacing without a label).
    func auditA11y(
        named name: String,
        audit: XCUIAccessibilityAuditType = .defaultStableSet,
        strict: Bool = false,
        ignoring ignoreList: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var captured: [String] = []
        do {
            try performAccessibilityAudit(for: audit) { [self] issue in
                if Self.shouldIgnore(issue: issue, ignoreList: ignoreList) {
                    return true
                }
                captured.append(self.describe(issue: issue))
                // In report-only mode, treat every issue as "ignored"
                // so `performAccessibilityAudit` doesn't throw — we'll
                // still attach the report below.
                return !strict
            }
        } catch {
            let detail = captured.joined(separator: "\n  • ")
            XCTFail(
                """
                Accessibility audit failed (strict) at '\(name)':
                  • \(detail.isEmpty ? error.localizedDescription : detail)
                """,
                file: file,
                line: line
            )
            return
        }

        // Always attach what we found (even when nothing failed). Lets
        // engineers spot drift screen-by-screen via the test report
        // without blocking CI. `XCTContext.runActivity` groups the
        // attachment under a named activity so it's easy to find.
        guard !captured.isEmpty else { return }
        let body = """
        Accessibility audit at '\(name)' (report-only) — \(captured.count) issue\(captured.count == 1 ? "" : "s"):
          • \(captured.joined(separator: "\n  • "))
        """
        XCTContext.runActivity(named: "A11y audit: \(name)") { activity in
            let attachment = XCTAttachment(string: body)
            attachment.name = "a11y-audit-\(name)"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    private func describe(issue: XCUIAccessibilityAuditIssue) -> String {
        let category = String(describing: issue.auditType)
        let detail = issue.compactDescription
        let elementId = issue.element?.identifier
        let elementLabel = issue.element?.label
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
