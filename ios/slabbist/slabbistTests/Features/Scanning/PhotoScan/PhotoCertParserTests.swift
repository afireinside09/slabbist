import Foundation
import Testing
@testable import slabbist

@Suite("PhotoCertParser")
struct PhotoCertParserTests {
    @Test("extracts every PSA cert from separate OCR lines")
    func extractsMultiplePSA() {
        let lines = ["GEM MT 10", "09812345", "MINT 9", "081234567"]
        let certs = PhotoCertParser.extractCerts(from: lines, grader: .PSA)
        #expect(certs == ["09812345", "081234567"])
    }

    @Test("dedupes a cert that OCR read on two lines")
    func dedupesRepeatedReads() {
        let lines = ["09812345", "PSA 10", "09812345"]
        let certs = PhotoCertParser.extractCerts(from: lines, grader: .PSA)
        #expect(certs == ["09812345"])
    }

    @Test("excludes a year and a short population count for PSA")
    func excludesNonCertNumbers() {
        // WHY: a 4-digit year (2022) and a 4-digit pop count must never be
        // mistaken for a cert. If length filtering regresses, this fails.
        let lines = ["POKEMON 2022", "POP 1234", "09812345"]
        let certs = PhotoCertParser.extractCerts(from: lines, grader: .PSA)
        #expect(certs == ["09812345"])
    }

    @Test("a 10-digit number is not picked up as a PSA cert")
    func tenDigitsNotPSA() {
        // WHY: BGS-length runs must not leak into a PSA scan.
        let lines = ["0123456789"]
        let certs = PhotoCertParser.extractCerts(from: lines, grader: .PSA)
        #expect(certs.isEmpty)
    }

    @Test("extracts BGS 10-digit certs")
    func extractsBGS() {
        let lines = ["BECKETT 9.5", "0123456789", "1234509876"]
        let certs = PhotoCertParser.extractCerts(from: lines, grader: .BGS)
        #expect(certs == ["0123456789", "1234509876"])
    }

    @Test("extracts SGC 7- and 8-digit certs")
    func extractsSGC() {
        let lines = ["SGC 10", "0011223", "00112233"]
        let certs = PhotoCertParser.extractCerts(from: lines, grader: .SGC)
        #expect(certs == ["0011223", "00112233"])
    }

    @Test("extracts alphanumeric TAG certs but not pure-digit runs")
    func extractsTAG() {
        // WHY: TAG's [A-Z0-9]{10,12} would also match a 10-digit number;
        // the letter requirement keeps plain digit runs out.
        let lines = ["TAG", "A1B2C3D4E5F6", "0123456789"]
        let certs = PhotoCertParser.extractCerts(from: lines, grader: .TAG)
        #expect(certs == ["A1B2C3D4E5F6"])
    }

    @Test("empty input yields empty output")
    func emptyInput() {
        #expect(PhotoCertParser.extractCerts(from: [], grader: .PSA).isEmpty)
    }
}
