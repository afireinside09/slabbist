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

    @Test("SecondaryIconButton renders")
    func secondaryIconButtonRenders() {
        let host = UIHostingController(
            rootView: SecondaryIconButton(systemIcon: "xmark", action: {})
        )
        #expect(host.view != nil)
    }

    @Test("PillToggle renders")
    @MainActor
    func pillToggleRenders() {
        struct Host: View {
            @State var selection: String = "a"
            var body: some View {
                PillToggle(
                    selection: $selection,
                    options: [("a", "One"), ("b", "Two")],
                    style: .accent
                )
            }
        }
        let host = UIHostingController(rootView: Host())
        #expect(host.view != nil)
    }

    @Test("StatStrip renders")
    func statStripRenders() {
        let host = UIHostingController(rootView: StatStrip(items: [
            .init(label: "Cards", value: "12"),
            .init(label: "Value", value: "$4.1k"),
            .init(label: "Change", value: "+2.4%"),
        ]))
        #expect(host.view != nil)
    }
}
