import Testing
@testable import ForgeLoopTUI

@Suite("Style Capability Degradation")
struct CapabilityStyleTests {

    @Test("rgb foreground renders truecolor on truecolor capability")
    func testRGBForegroundTrueColor() {
        let spec = StyleSpec(foreground: .rgb(255, 128, 0))
        let sgr = Style.renderSGR(spec, capability: .truecolor)
        #expect(sgr == "\u{1B}[38;2;255;128;0m")
    }

    @Test("rgb foreground degrades to indexed on ansi256")
    func testRGBForegroundAnsi256() {
        let spec = StyleSpec(foreground: .rgb(255, 128, 0))
        let sgr = Style.renderSGR(spec, capability: .ansi256)
        // nearest indexed for orange
        #expect(sgr == "\u{1B}[38;5;214m")
    }

    @Test("rgb foreground degrades to standard on ansi16")
    func testRGBForegroundAnsi16() {
        let spec = StyleSpec(foreground: .rgb(255, 128, 0))
        let sgr = Style.renderSGR(spec, capability: .ansi16)
        // nearest standard to orange is yellow (33)
        #expect(sgr == "\u{1B}[33m")
    }

    @Test("rgb foreground degrades to plain on plain capability")
    func testRGBForegroundPlain() {
        let spec = StyleSpec(foreground: .rgb(255, 128, 0))
        let sgr = Style.renderSGR(spec, capability: .plain)
        #expect(sgr.isEmpty)
    }

    @Test("indexed foreground renders indexed on ansi256/truecolor")
    func testIndexedForegroundAnsi256() {
        let spec = StyleSpec(foreground: .indexed(196))
        let sgr256 = Style.renderSGR(spec, capability: .ansi256)
        let sgrTrue = Style.renderSGR(spec, capability: .truecolor)
        #expect(sgr256 == "\u{1B}[38;5;196m")
        #expect(sgrTrue == "\u{1B}[38;5;196m")
    }

    @Test("indexed foreground degrades to standard on ansi16")
    func testIndexedForegroundAnsi16() {
        let spec = StyleSpec(foreground: .indexed(196))
        let sgr = Style.renderSGR(spec, capability: .ansi16)
        // 196 maps to pure red in the cube, nearest standard is red (31)
        #expect(sgr == "\u{1B}[31m")
    }

    @Test("rgb background renders truecolor on truecolor")
    func testRGBBackgroundTrueColor() {
        let spec = StyleSpec(background: .rgb(0, 128, 255))
        let sgr = Style.renderSGR(spec, capability: .truecolor)
        #expect(sgr == "\u{1B}[48;2;0;128;255m")
    }

    @Test("rgb background degrades to indexed on ansi256")
    func testRGBBackgroundAnsi256() {
        let spec = StyleSpec(background: .rgb(0, 128, 255))
        let sgr = Style.renderSGR(spec, capability: .ansi256)
        #expect(sgr == "\u{1B}[48;5;39m")
    }

    @Test("rgb background degrades to standard on ansi16")
    func testRGBBackgroundAnsi16() {
        let spec = StyleSpec(background: .rgb(0, 128, 255))
        let sgr = Style.renderSGR(spec, capability: .ansi16)
        // nearest standard to cyan-ish blue is cyan (46)
        #expect(sgr == "\u{1B}[46m")
    }

    @Test("bold + rgb composite degrades correctly")
    func testCompositeDegradation() {
        let spec = StyleSpec(bold: true, foreground: .rgb(255, 0, 0))
        let sgrTrue = Style.renderSGR(spec, capability: .truecolor)
        let sgr256 = Style.renderSGR(spec, capability: .ansi256)
        let sgr16 = Style.renderSGR(spec, capability: .ansi16)
        #expect(sgrTrue == "\u{1B}[1;38;2;255;0;0m")
        #expect(sgr256 == "\u{1B}[1;38;5;196m")
        #expect(sgr16 == "\u{1B}[1;31m")
    }

    @Test("existing Style methods remain backward compatible on ansi16")
    func testExistingMethodsAnsi16() {
        #expect(Style.error("x", mode: .ansi, capability: .ansi16) == "\u{1B}[31mx\u{1B}[0m")
        #expect(Style.user("x", mode: .ansi, capability: .ansi16) == "\u{1B}[36mx\u{1B}[0m")
        #expect(Style.prompt("x", mode: .ansi, capability: .ansi16) == "\u{1B}[1;36mx\u{1B}[0m")
        #expect(Style.header("x", mode: .ansi, capability: .ansi16) == "\u{1B}[1;95mx\u{1B}[0m")
    }

    @Test("plain mode ignores capability entirely")
    func testPlainModeIgnoresCapability() {
        let spec = StyleSpec(bold: true, foreground: .rgb(255, 0, 0))
        let text = Style.styled("x", spec: spec, mode: .plain, capability: .truecolor)
        #expect(text == "x")
    }
}
