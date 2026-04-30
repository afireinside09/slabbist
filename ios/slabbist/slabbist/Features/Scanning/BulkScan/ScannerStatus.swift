import Foundation

/// Live UI state for the bulk-scan pipeline. Drives the corner-bracket
/// overlay color and the status pill. Transitions are driven by:
///   - per-frame OCR (idle ⇄ reading)
///   - the recognizer firing a stable cert (→ lookingUp)
///   - the cert-lookup edge function returning (→ resolved | failed)
@MainActor
enum ScannerStatus: Equatable {
    case idle
    case reading
    case lookingUp(grader: Grader, certNumber: String)
    case resolved(productLabel: String)
    case failed(message: String)

    var pillText: String {
        switch self {
        case .idle: return "Position slab in frame"
        case .reading: return "Reading…"
        case .lookingUp(let grader, let cert): return "Looking up \(grader.rawValue) \(cert)"
        case .resolved(let label): return label
        case .failed(let msg): return msg
        }
    }

    /// Tier the UI maps colors to. Resolved is the only "success" green —
    /// every active state stays gold so the eye can track progress without
    /// the feedback flickering.
    enum Tone { case neutral, active, success, error }

    var tone: Tone {
        switch self {
        case .idle: return .neutral
        case .reading, .lookingUp: return .active
        case .resolved: return .success
        case .failed: return .error
        }
    }
}

/// One-shot event emitted by `BulkScanViewModel.triggerCertLookup` so the
/// view can drive the visible status. Decoupled from `ScannerStatus` so the
/// VM doesn't need to know about UI tones.
enum LookupEvent: Equatable {
    case started(grader: Grader, certNumber: String)
    case resolved(productLabel: String)
    case failed(reason: String)
}
