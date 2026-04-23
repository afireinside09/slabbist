import Testing
import SwiftUI
import UIKit
@testable import slabbist

@Suite("Design system smoke")
@MainActor
struct PrimitiveSmokeTests {
    @Test("Instrument Serif Regular loads from bundle")
    func instrumentSerifRegularLoads() {
        let font = UIFont(name: "InstrumentSerif-Regular", size: 12)
        #expect(
            font != nil,
            "InstrumentSerif-Regular.ttf not found — check Resources/Fonts/ files and INFOPLIST_KEY_UIAppFonts."
        )
    }

    @Test("Instrument Serif Italic loads from bundle")
    func instrumentSerifItalicLoads() {
        let font = UIFont(name: "InstrumentSerif-Italic", size: 12)
        #expect(
            font != nil,
            "InstrumentSerif-Italic.ttf not found — check Resources/Fonts/ files and INFOPLIST_KEY_UIAppFonts."
        )
    }

    @Test("KickerLabel renders")
    func kickerLabelRenders() {
        let host = UIHostingController(rootView: KickerLabel("CURRENT LOTS"))
        _ = host.view // forces layout; non-nil if view graph compiles
        #expect(host.view != nil)
    }

    @Test("SlabCard renders with content")
    func slabCardRenders() {
        let host = UIHostingController(rootView: SlabCard {
            Text("body")
        })
        #expect(host.view != nil)
    }

    @Test("PrimaryGoldButton renders")
    func primaryGoldButtonRenders() {
        let host = UIHostingController(
            rootView: PrimaryGoldButton(title: "Start scanning", action: {})
        )
        #expect(host.view != nil)
    }
}
