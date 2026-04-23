import Foundation
import Vision

/// Result of a single frame's recognition pass.
struct CertCandidate: Equatable {
    let grader: Grader
    let certNumber: String
    let confidence: Double
    let rawText: String
}

enum CertOCRConfig {
    static let stableFrameCount: Int = 3
    static let stableWindowMillis: Int = 200
    static let stableConfidenceThreshold: Double = 0.85
    static let fallbackConfidenceThreshold: Double = 0.50
}

/// Identifies a grader + cert number from text recognition candidates.
/// The stability gate (N matching reads in T ms) is applied upstream by
/// `CertOCRRecognizer.ingest`.
enum CertOCRPatterns {
    /// One pattern per grader. Each pattern captures the cert digits
    /// into group 1. Keyword proximity check runs separately.
    static let patterns: [(grader: Grader, keyword: String, regex: NSRegularExpression)] = {
        func compile(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        return [
            (.PSA, "PSA",     compile(#"\b(\d{8,9})\b"#)),
            (.BGS, "BGS",     compile(#"\b(\d{10})\b"#)),
            (.BGS, "BECKETT", compile(#"\b(\d{10})\b"#)),
            (.CGC, "CGC",     compile(#"\b(\d{10})\b"#)),
            (.SGC, "SGC",     compile(#"\b(\d{7,8})\b"#)),
            (.TAG, "TAG",     compile(#"\b([A-Z0-9]{10,12})\b"#))
        ]
    }()

    static func match(in text: String) -> CertCandidate? {
        let upper = text.uppercased()
        for (grader, keyword, regex) in patterns {
            guard upper.contains(keyword) else { continue }
            let range = NSRange(upper.startIndex..<upper.endIndex, in: upper)
            guard let match = regex.firstMatch(in: upper, options: [], range: range) else { continue }
            guard match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: upper) else { continue }
            let cert = String(upper[r])
            return CertCandidate(grader: grader, certNumber: cert, confidence: 1.0, rawText: text)
        }
        return nil
    }
}

@MainActor
final class CertOCRRecognizer {
    private struct SeenRead {
        let candidate: CertCandidate
        let at: Date
    }

    private var recent: [SeenRead] = []
    private let clock: () -> Date

    init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
    }

    /// Feed the recognizer a single frame's text candidates (e.g. from Vision).
    /// Returns a "stable" candidate if the same `(grader, certNumber)` has
    /// appeared `stableFrameCount` times in the last `stableWindowMillis`.
    func ingest(textCandidates: [String], visionConfidence: Double) -> CertCandidate? {
        guard visionConfidence >= CertOCRConfig.fallbackConfidenceThreshold else {
            return nil
        }

        let now = clock()
        for text in textCandidates {
            guard let cand = CertOCRPatterns.match(in: text) else { continue }
            recent.append(SeenRead(candidate: cand, at: now))
        }

        let windowStart = now.addingTimeInterval(-Double(CertOCRConfig.stableWindowMillis) / 1000.0)
        recent.removeAll { $0.at < windowStart }

        let grouped = Dictionary(grouping: recent) { "\($0.candidate.grader.rawValue)|\($0.candidate.certNumber)" }
        guard let stable = grouped.first(where: { $0.value.count >= CertOCRConfig.stableFrameCount }),
              let first = stable.value.first else { return nil }

        guard visionConfidence >= CertOCRConfig.stableConfidenceThreshold else {
            return nil
        }

        // Reset so we don't keep re-firing on the same stable window.
        recent.removeAll()
        return CertCandidate(
            grader: first.candidate.grader,
            certNumber: first.candidate.certNumber,
            confidence: visionConfidence,
            rawText: first.candidate.rawText
        )
    }
}
