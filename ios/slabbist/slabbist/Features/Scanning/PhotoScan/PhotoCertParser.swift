import Foundation

/// Multi-cert extraction for the photo-scan flow. The grader is declared by
/// the user before capture, so there is no grader inference — given the
/// grader and the OCR text lines, return every distinct cert number matching
/// that grader's format, in first-appearance order.
///
/// Pure (no Vision/UIKit dependency) so it is fully unit-testable. The
/// per-grader formats mirror `CertOCRPatterns` and `ManualEntrySheet.validate`
/// — kept local here to avoid a Vision dependency. If these formats ever
/// consolidate, change all three together.
enum PhotoCertParser {
    private static func pattern(for grader: Grader) -> NSRegularExpression {
        let body: String
        switch grader {
        case .PSA:       body = #"\b(\d{8,9})\b"#
        case .BGS, .CGC: body = #"\b(\d{10})\b"#
        case .SGC:       body = #"\b(\d{7,8})\b"#
        case .TAG:       body = #"\b([A-Z0-9]{10,12})\b"#
        }
        // `.caseInsensitive` mirrors CertOCRPatterns; input is already
        // uppercased so it's effectively a no-op for these patterns.
        return try! NSRegularExpression(pattern: body, options: [.caseInsensitive])
    }

    static func extractCerts(from recognizedStrings: [String], grader: Grader) -> [String] {
        let regex = pattern(for: grader)
        var seen = Set<String>()
        var result: [String] = []
        for line in recognizedStrings {
            let upper = line.uppercased()
            let range = NSRange(upper.startIndex..<upper.endIndex, in: upper)
            for m in regex.matches(in: upper, options: [], range: range) {
                guard m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: upper) else { continue }
                let cert = String(upper[r])
                // TAG patterns also match pure 10-digit runs; require a letter
                // so a BGS-shaped number can't masquerade as a TAG cert.
                if grader == .TAG && !cert.contains(where: \.isLetter) { continue }
                if seen.insert(cert).inserted { result.append(cert) }
            }
        }
        return result
    }
}
