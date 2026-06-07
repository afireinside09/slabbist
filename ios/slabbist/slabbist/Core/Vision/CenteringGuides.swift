import Foundation

/// The eight axis-aligned guide lines for one card side, expressed in
/// normalized image space (`0...1`). Left/right edges are X-positions
/// (fraction of width); top/bottom edges are Y-positions (fraction of
/// height). The four *outer* lines mark the card edge; the four *inner*
/// lines mark the printed frame edge. Border width per side = inner − outer.
///
/// This is the source of truth a drag interaction mutates and the only
/// input the ratio math needs — it carries no screen, zoom, or rotation
/// state, so the measured ratio is invariant to how the image is displayed.
nonisolated struct CenteringGuides: Equatable, Sendable {
    var outerLeft: Double
    var innerLeft: Double
    var innerRight: Double
    var outerRight: Double
    var outerTop: Double
    var innerTop: Double
    var innerBottom: Double
    var outerBottom: Double

    /// A sensible starting layout for a roughly-centered card: outer lines
    /// at an 8% inset, inner lines at a 16% inset (an ~8% border).
    static let centeredDefault = CenteringGuides(
        outerLeft: 0.08, innerLeft: 0.16, innerRight: 0.84, outerRight: 0.92,
        outerTop: 0.08, innerTop: 0.16, innerBottom: 0.84, outerBottom: 0.92
    )

    subscript(edge: GuideEdge) -> Double {
        get {
            switch edge {
            case .outerLeft: outerLeft
            case .innerLeft: innerLeft
            case .innerRight: innerRight
            case .outerRight: outerRight
            case .outerTop: outerTop
            case .innerTop: innerTop
            case .innerBottom: innerBottom
            case .outerBottom: outerBottom
            }
        }
        set {
            switch edge {
            case .outerLeft: outerLeft = newValue
            case .innerLeft: innerLeft = newValue
            case .innerRight: innerRight = newValue
            case .outerRight: outerRight = newValue
            case .outerTop: outerTop = newValue
            case .innerTop: innerTop = newValue
            case .innerBottom: innerBottom = newValue
            case .outerBottom: outerBottom = newValue
            }
        }
    }
}

/// Identifies one of the eight guide lines. `CaseIterable` order is used as
/// stable `ForEach` identity for the draggable handles.
nonisolated enum GuideEdge: CaseIterable, Hashable, Sendable {
    case outerLeft, innerLeft, innerRight, outerRight
    case outerTop, innerTop, innerBottom, outerBottom

    /// `true` for left/right edges — drawn as vertical lines, dragged along X.
    /// `false` for top/bottom edges — drawn as horizontal lines, dragged along Y.
    var isVertical: Bool {
        switch self {
        case .outerLeft, .innerLeft, .innerRight, .outerRight: true
        case .outerTop, .innerTop, .innerBottom, .outerBottom: false
        }
    }

    var isInner: Bool {
        switch self {
        case .innerLeft, .innerRight, .innerTop, .innerBottom: true
        default: false
        }
    }
}
