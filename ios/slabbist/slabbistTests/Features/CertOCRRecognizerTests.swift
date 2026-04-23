import Foundation
import Testing
@testable import slabbist

@Suite("CertOCRPatterns")
struct CertOCRPatternTests {
    @Test("matches a PSA 9-digit cert near 'PSA' keyword")
    func matchesPSA() {
        let sample = "PSA MINT 9 — 12345678\nPOKEMON — CHARIZARD"
        let match = CertOCRPatterns.match(in: sample)
        #expect(match?.grader == .PSA)
        #expect(match?.certNumber == "12345678")
    }

    @Test("matches BGS 10-digit cert near 'BECKETT'")
    func matchesBGS() {
        let sample = "BECKETT GRADING SERVICE 9.5 GEM MINT 0123456789"
        let match = CertOCRPatterns.match(in: sample)
        #expect(match?.grader == .BGS)
        #expect(match?.certNumber == "0123456789")
    }

    @Test("matches CGC 10-digit cert near 'CGC'")
    func matchesCGC() {
        let sample = "CGC TRADING CARDS\n9876543210\nPERFECT 10"
        let match = CertOCRPatterns.match(in: sample)
        #expect(match?.grader == .CGC)
        #expect(match?.certNumber == "9876543210")
    }

    @Test("matches SGC 8-digit cert near 'SGC'")
    func matchesSGC() {
        let sample = "SGC 10 PRISTINE 00112233"
        let match = CertOCRPatterns.match(in: sample)
        #expect(match?.grader == .SGC)
        #expect(match?.certNumber == "00112233")
    }

    @Test("matches TAG cert near 'TAG'")
    func matchesTAG() {
        let sample = "TAG GRADING A1B2C3D4E5F6"
        let match = CertOCRPatterns.match(in: sample)
        #expect(match?.grader == .TAG)
        #expect(match?.certNumber == "A1B2C3D4E5F6")
    }

    @Test("does not match a digit sequence without a grader keyword")
    func rejectsUnlabeledDigits() {
        let sample = "POKEMON TCG BASE SET 1999 — 12345678"
        let match = CertOCRPatterns.match(in: sample)
        #expect(match == nil)
    }
}

@Suite("CertOCRRecognizer stability gate")
@MainActor
struct CertOCRRecognizerStabilityTests {
    @Test("does not fire on a single confident read")
    func singleReadNoFire() {
        var now = Date(timeIntervalSince1970: 1_000)
        let r = CertOCRRecognizer(clock: { now })
        let result = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95)
        #expect(result == nil)

        now = now.addingTimeInterval(0.010)
        #expect(r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95) == nil)
    }

    @Test("fires on three confident reads of the same cert within window")
    func firesOnStableReads() {
        var now = Date(timeIntervalSince1970: 2_000)
        let r = CertOCRRecognizer(clock: { now })

        _ = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95)
        now = now.addingTimeInterval(0.040)
        _ = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95)
        now = now.addingTimeInterval(0.040)
        let result = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95)

        #expect(result?.grader == .PSA)
        #expect(result?.certNumber == "12345678")
    }

    @Test("does not fire below the stable confidence threshold")
    func skipsLowConfidence() {
        var now = Date(timeIntervalSince1970: 3_000)
        let r = CertOCRRecognizer(clock: { now })
        _ = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.70)
        now = now.addingTimeInterval(0.040)
        _ = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.70)
        now = now.addingTimeInterval(0.040)
        let result = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.70)
        #expect(result == nil)
    }

    @Test("skips ingestion entirely below fallback confidence threshold")
    func skipsBelowFallback() {
        let now = Date(timeIntervalSince1970: 4_000)
        let r = CertOCRRecognizer(clock: { now })
        let result = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.30)
        #expect(result == nil)
    }

    @Test("does not fire when reads fall outside the stable window")
    func windowExpires() {
        var now = Date(timeIntervalSince1970: 5_000)
        let r = CertOCRRecognizer(clock: { now })

        _ = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95)
        now = now.addingTimeInterval(0.5)   // beyond 200ms window
        _ = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95)
        now = now.addingTimeInterval(0.5)
        let result = r.ingest(textCandidates: ["PSA MINT 12345678"], visionConfidence: 0.95)
        #expect(result == nil)
    }
}
