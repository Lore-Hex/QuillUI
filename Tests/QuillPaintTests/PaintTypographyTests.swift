import Foundation
import Testing
@testable import QuillPaint

@Suite("Paint typography")
struct PaintTypographyTests {
    @Test("Mac font tokens match regular-control metrics")
    func macFontTokens() {
        #expect(MacFonts.controlLabel.family == MacFontResolution.preferredMacTextFamily)
        #expect(MacFonts.controlLabel.size == 13)
        #expect(MacFonts.controlLabel.weight == 400)

        #expect(MacFonts.controlLabelEmphasized.size == 13)
        #expect(MacFonts.controlLabelEmphasized.weight == 600)

        #expect(MacFonts.titlebarTitle.size == 13)
        #expect(MacFonts.titlebarTitle.weight == 400)
    }

    @Test("Mac font resolution prefers SF Pro Text")
    func resolutionPrefersSFProText() {
        let resolved = MacFontResolution.resolve(
            MacFonts.controlLabel,
            availableFamilies: ["Inter", "SF Pro Text", "Helvetica Neue"]
        )

        #expect(resolved.family == "SF Pro Text")
        #expect(resolved.size == 13)
        #expect(resolved.weight == 400)
    }

    @Test("Mac font resolution falls back through Inter, Helvetica Neue, then system")
    func resolutionFallbacks() {
        #expect(MacFontResolution.resolvedFamily(availableFamilies: ["Inter"]) == "Inter")
        #expect(MacFontResolution.resolvedFamily(availableFamilies: ["Helvetica Neue"]) == "Helvetica Neue")
        #expect(MacFontResolution.resolvedFamily(availableFamilies: []) == MacFontResolution.systemDefaultFamily)
    }

    @Test("Mac font resolution matches family names case-insensitively")
    func resolutionIsCaseInsensitive() {
        #expect(MacFontResolution.resolvedFamily(availableFamilies: ["inter"]) == "Inter")
    }

    @Test("Custom PaintFont families are left alone")
    func customFamiliesRemainCustom() {
        let custom = PaintFont(family: "Quill Test Sans", size: 17, weight: 700)
        #expect(MacFontResolution.resolve(custom, availableFamilies: []) == custom)

        let explicitInter = PaintFont(family: "Inter", size: 13, weight: 400)
        #expect(MacFontResolution.resolve(explicitInter, availableFamilies: ["SF Pro Text"]) == explicitInter)
    }
}
