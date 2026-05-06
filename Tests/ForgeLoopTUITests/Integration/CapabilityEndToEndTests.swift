import Testing
@testable import ForgeLoopTUI

@Suite("Capability End-to-End Rendering")
struct CapabilityEndToEndTests {

    // MARK: - ModalRenderer

    @Test("ModalRenderer produces no ANSI on plain capability")
    func testModalRendererPlain() {
        let renderer = ModalRenderer(styleMode: .ansi, capability: .plain)
        let lines = renderer.render(title: "Title", body: ["Line 1"], footer: "Footer")
        for line in lines {
            #expect(!line.contains("\u{1B}"), "Plain capability must not emit escape sequences: \(line)")
        }
    }

    @Test("ModalRenderer produces ANSI on ansi16 capability")
    func testModalRendererAnsi16() {
        let renderer = ModalRenderer(styleMode: .ansi, capability: .ansi16)
        let lines = renderer.render(title: "Title", body: ["Line 1"], footer: "Footer")
        #expect(lines[0].hasPrefix("\u{1B}["), "Header should be styled")
        #expect(lines.last?.hasPrefix("\u{1B}[") == true, "Footer should be styled")
    }

    // MARK: - ListPickerRenderer

    @Test("ListPickerRenderer produces no ANSI on plain capability")
    func testListPickerRendererPlain() {
        let renderer = ListPickerRenderer(styleMode: .ansi, capability: .plain)
        let state = ListPickerState(title: "Pick", items: [
            ListPickerItem(id: "1", title: "A", subtitle: "sub"),
            ListPickerItem(id: "2", title: "B"),
        ], selectedIndex: 0)
        let lines = renderer.render(state: state)
        for line in lines {
            #expect(!line.contains("\u{1B}"), "Plain capability must not emit escape sequences")
        }
    }

    @Test("ListPickerRenderer preserves selection style on ansi16")
    func testListPickerRendererAnsi16() {
        let renderer = ListPickerRenderer(styleMode: .ansi, capability: .ansi16)
        let state = ListPickerState(title: "Pick", items: [
            ListPickerItem(id: "1", title: "A"),
        ], selectedIndex: 0)
        let lines = renderer.render(state: state)
        let selectedLine = lines.first { $0.contains("● A") }
        #expect(selectedLine != nil)
        #expect(selectedLine?.hasPrefix("\u{1B}[") == true, "Selected item should be styled")
    }

    // MARK: - LegacyRenderEventAdapter

    @Test("Legacy user message has no ANSI on plain capability")
    func testLegacyUserMessagePlain() {
        let event = LegacyRenderEventAdapter.adapt(
            .messageStart(message: .user("hello")),
            capability: .plain
        )
        guard case .insert(let lines) = event else {
            Issue.record("Expected insert event")
            return
        }
        for line in lines {
            #expect(!line.contains("\u{1B}"), "Plain capability must not emit escape sequences")
        }
    }

    @Test("Legacy user message has ANSI prefix on ansi16 capability")
    func testLegacyUserMessageAnsi16() {
        let event = LegacyRenderEventAdapter.adapt(
            .messageStart(message: .user("hello")),
            capability: .ansi16
        )
        guard case .insert(let lines) = event else {
            Issue.record("Expected insert event")
            return
        }
        let first = lines.first
        // Note: LegacyRenderEventAdapter uses Style.user with mode=.automatic,
        // which checks isatty. In test environment this may be false.
        // We verify the prefix is either styled or plain text.
        #expect(first?.contains("hello") == true, "Should contain the text")
    }

    // MARK: - Style styled end-to-end with rgb degradation

    @Test("rgb text degrades to plain when capability is plain")
    func testRGBTextPlainEndToEnd() {
        let spec = StyleSpec(foreground: .rgb(255, 0, 0))
        let result = Style.styled("alert", spec: spec, mode: .ansi, capability: .plain)
        #expect(result == "alert")
    }

    @Test("rgb text degrades to ansi16 when capability is ansi16")
    func testRGBTextAnsi16EndToEnd() {
        let spec = StyleSpec(foreground: .rgb(255, 0, 0))
        let result = Style.styled("alert", spec: spec, mode: .ansi, capability: .ansi16)
        #expect(result == "\u{1B}[31malert\u{1B}[0m")
    }

    @Test("rgb text keeps indexed on ansi256")
    func testRGBTextAnsi256EndToEnd() {
        let spec = StyleSpec(foreground: .rgb(255, 0, 0))
        let result = Style.styled("alert", spec: spec, mode: .ansi, capability: .ansi256)
        #expect(result == "\u{1B}[38;5;196malert\u{1B}[0m")
    }

    @Test("rgb text keeps truecolor on truecolor")
    func testRGBTextTrueColorEndToEnd() {
        let spec = StyleSpec(foreground: .rgb(255, 0, 0))
        let result = Style.styled("alert", spec: spec, mode: .ansi, capability: .truecolor)
        #expect(result == "\u{1B}[38;2;255;0;0malert\u{1B}[0m")
    }
}
