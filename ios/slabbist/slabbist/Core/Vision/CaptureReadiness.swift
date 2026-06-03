/// Snapshot of live capture quality, published from the camera sample queue to
/// the view model. Drives both the shutter-enabled state (`isReady`) and the
/// QualityChip copy (`message`).
struct CaptureReadiness: Equatable, Sendable {
    var cardDetected: Bool
    var sharp: Bool
    var glareOK: Bool
    var steady: Bool

    var isReady: Bool { cardDetected && sharp && glareOK && steady }

    /// First failing reason in priority order, or nil when ready.
    var message: String? {
        if !cardDetected { return "Card not detected — frame the whole card." }
        if !sharp { return "Too blurry — hold steady and let it focus." }
        if !glareOK { return "Too much glare — angle away from direct light." }
        if !steady { return "Hold still…" }
        return nil
    }
}
