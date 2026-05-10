import Testing
@testable import slabbist

struct VendorEditSheetParseTests {
    @Test func trimsDisplayName() {
        #expect(VendorEditSheet.normalize(displayName: "  Acme  ") == "Acme")
    }

    @Test func rejectsEmptyDisplayName() {
        #expect(VendorEditSheet.normalize(displayName: "   ") == nil)
    }
}
