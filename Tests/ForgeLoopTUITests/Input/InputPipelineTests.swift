import Testing
@testable import ForgeLoopTUI

@Suite("InputPipeline")
struct InputPipelineTests {

    // MARK: - Bracketed Paste

    @Test("complete paste in one feed")
    func testCompletePasteInOneFeed() {
        let pipe = InputPipeline()
        let events = pipe.feed([0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
            + Array("hello".utf8)
            + [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E])
        #expect(events.count == 1)
        #expect(events[0] == KeyEvent(key: .paste("hello")))
    }

    @Test("paste split across two feeds")
    func testPasteSplitAcrossFeeds() {
        let pipe = InputPipeline()
        let e1 = pipe.feed([0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
            + Array("hel".utf8))
        #expect(e1.isEmpty)

        let e2 = pipe.feed(Array("lo".utf8)
            + [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E])
        #expect(e2.count == 1)
        #expect(e2[0] == KeyEvent(key: .paste("hello")))
    }

    @Test("paste markers in separate feeds")
    func testPasteMarkersInSeparateFeeds() {
        let pipe = InputPipeline()
        let e1 = pipe.feed([0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E])
        #expect(e1.isEmpty)

        let e2 = pipe.feed([0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E])
        #expect(e2.count == 1)
        #expect(e2[0] == KeyEvent(key: .paste("")))
    }

    @Test("CSI inside paste is not parsed as arrow key")
    func testCSIInsidePaste() {
        let pipe = InputPipeline()
        // ESC[200~ ESC[A ESC[201~  — 中间 ESC[A 应在 paste 内作为文本
        let events = pipe.feed([
            0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E, // ESC[200~
            0x1B, 0x5B, 0x41,                     // ESC[A
            0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E, // ESC[201~
        ])
        #expect(events.count == 1)
        #expect(events[0] == KeyEvent(key: .paste("\u{1B}[A")))
    }

    @Test("paste with UTF-8 content")
    func testPasteWithUTF8() {
        let pipe = InputPipeline()
        let content = "中🚀"
        var bytes: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
        bytes.append(contentsOf: content.utf8)
        bytes.append(contentsOf: [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E])
        let events = pipe.feed(bytes)
        #expect(events.count == 1)
        #expect(events[0] == KeyEvent(key: .paste(content)))
    }

    @Test("normal keys before and after paste")
    func testNormalKeysAroundPaste() {
        let pipe = InputPipeline()
        var bytes: [UInt8] = Array("a".utf8)
        bytes.append(contentsOf: [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E])
        bytes.append(contentsOf: Array("x".utf8))
        bytes.append(contentsOf: [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E])
        bytes.append(contentsOf: Array("b".utf8))
        let events = pipe.feed(bytes)
        #expect(events == [
            KeyEvent(key: .character("a")),
            KeyEvent(key: .paste("x")),
            KeyEvent(key: .character("b")),
        ])
    }

    @Test("unclosed paste on flush emits paste event")
    func testUnclosedPasteOnFlush() {
        let pipe = InputPipeline()
        let e1 = pipe.feed([0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
            + Array("hello".utf8))
        #expect(e1.isEmpty)

        let e2 = pipe.flush()
        #expect(e2.count == 1)
        #expect(e2[0] == KeyEvent(key: .paste("hello")))
    }

    @Test("flush after closed paste is idempotent")
    func testFlushAfterClosedPaste() {
        let pipe = InputPipeline()
        _ = pipe.feed([0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
            + [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E])
        let e2 = pipe.flush()
        #expect(e2.isEmpty)
    }

    @Test("empty paste")
    func testEmptyPaste() {
        let pipe = InputPipeline()
        let events = pipe.feed([
            0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E,
            0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E,
        ])
        #expect(events.count == 1)
        #expect(events[0] == KeyEvent(key: .paste("")))
    }

    @Test("escape sequence inside paste is preserved as text")
    func testEscapeInsidePaste() {
        let pipe = InputPipeline()
        // ESC[200~ ESC OP ESC[201~  — SS3 F1 序列在 paste 内作为文本
        let events = pipe.feed([
            0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E, // ESC[200~
            0x1B, 0x4F, 0x50,                     // ESC OP (SS3 F1)
            0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E, // ESC[201~
        ])
        #expect(events.count == 1)
        #expect(events[0] == KeyEvent(key: .paste("\u{1B}OP")))
    }

    // MARK: - Normal key passthrough

    @Test("arrow keys pass through normally")
    func testArrowKeysPassthrough() {
        let pipe = InputPipeline()
        let events = pipe.feed([0x1B, 0x5B, 0x41, 0x1B, 0x5B, 0x42])
        #expect(events == [KeyEvent(key: .up), KeyEvent(key: .down)])
    }

    @Test("SS3 arrow keys pass through without regression")
    func testSS3ArrowKeysPassthrough() {
        let pipe = InputPipeline()
        let events = pipe.feed([
            0x1B, 0x4F, 0x41, // ESC O A = Up
            0x1B, 0x4F, 0x42, // ESC O B = Down
        ])
        #expect(events == [KeyEvent(key: .up), KeyEvent(key: .down)])
    }

    @Test("SS3 function keys pass through without regression")
    func testSS3FunctionKeysPassthrough() {
        let pipe = InputPipeline()
        let events = pipe.feed([
            0x1B, 0x4F, 0x50, // ESC O P = F1
            0x1B, 0x4F, 0x51, // ESC O Q = F2
        ])
        #expect(events == [KeyEvent(key: .f1), KeyEvent(key: .f2)])
    }

    @Test("mixed normal input without paste")
    func testMixedNormalInput() {
        let pipe = InputPipeline()
        var bytes: [UInt8] = Array("hi".utf8)
        bytes.append(contentsOf: [0x0D]) // Enter
        bytes.append(contentsOf: [0x1B, 0x5B, 0x43]) // Right
        let events = pipe.feed(bytes)
        #expect(events == [
            KeyEvent(key: .character("h")),
            KeyEvent(key: .character("i")),
            KeyEvent(key: .enter),
            KeyEvent(key: .right),
        ])
    }

    // MARK: - ESC Timeout

    @Test("ESC alone triggers escape after timeout")
    func testESCAloneTimeout() {
        let clock = TestInputClock()
        let pipe = InputPipeline(clock: clock, escapeTimeoutNanoseconds: 50_000_000)
        let e1 = pipe.feed([0x1B])
        #expect(e1.isEmpty)

        clock.advance(by: 50_000_000)
        let e2 = pipe.tick()
        #expect(e2 == [KeyEvent(key: .escape)])
    }

    @Test("Alt+x within timeout window")
    func testAltXWithinWindow() {
        let clock = TestInputClock()
        let pipe = InputPipeline(clock: clock, escapeTimeoutNanoseconds: 50_000_000)
        let e1 = pipe.feed([0x1B])
        #expect(e1.isEmpty)

        clock.advance(by: 10_000_000)
        let e2 = pipe.feed([0x78]) // 'x'
        #expect(e2 == [KeyEvent(key: .character("x"), modifiers: .alt)])
    }

    @Test("ESC + CSI within timeout window")
    func testESCCSIWithinWindow() {
        let clock = TestInputClock()
        let pipe = InputPipeline(clock: clock, escapeTimeoutNanoseconds: 50_000_000)
        let e1 = pipe.feed([0x1B, 0x5B])
        #expect(e1.isEmpty)

        clock.advance(by: 10_000_000)
        let e2 = pipe.feed([0x41]) // 'A' → completes ESC[A
        #expect(e2 == [KeyEvent(key: .up)])
    }

    @Test("ESC alone then normal key after timeout")
    func testESCAloneThenNormalKeyAfterTimeout() {
        let clock = TestInputClock()
        let pipe = InputPipeline(clock: clock, escapeTimeoutNanoseconds: 50_000_000)
        let e1 = pipe.feed([0x1B])
        #expect(e1.isEmpty)

        clock.advance(by: 50_000_000)
        let e2 = pipe.tick()
        #expect(e2 == [KeyEvent(key: .escape)])

        let e3 = pipe.feed([0x78])
        #expect(e3 == [KeyEvent(key: .character("x"))])
    }

    @Test("flush cancels pending escape and emits it immediately")
    func testFlushCancelsPendingEscape() {
        let clock = TestInputClock()
        let pipe = InputPipeline(clock: clock, escapeTimeoutNanoseconds: 50_000_000)
        let e1 = pipe.feed([0x1B])
        #expect(e1.isEmpty)

        let e2 = pipe.flush()
        #expect(e2 == [KeyEvent(key: .escape)])
    }

    @Test("unclosed paste with trailing isolated ESC on flush")
    func testUnclosedPasteWithTrailingESC() {
        let pipe = InputPipeline()
        var bytes: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E] // ESC[200~
        bytes.append(contentsOf: Array("abc".utf8))
        bytes.append(0x1B) // trailing isolated ESC
        let e1 = pipe.feed(bytes)
        #expect(e1.isEmpty)

        let e2 = pipe.flush()
        #expect(e2.count == 1)
        #expect(e2[0] == KeyEvent(key: .paste("abc\u{1B}")))
    }

    @Test("unclosed paste with incomplete UTF-8 on flush")
    func testUnclosedPasteWithIncompleteUTF8() {
        let pipe = InputPipeline()
        var bytes: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E] // ESC[200~
        bytes.append(contentsOf: Array("ab".utf8))
        bytes.append(contentsOf: [0xE4, 0xB8]) // incomplete UTF-8 for "中"
        let e1 = pipe.feed(bytes)
        #expect(e1.isEmpty)

        let e2 = pipe.flush()
        #expect(e2.count == 1)
        #expect(e2[0] == KeyEvent(key: .paste("ab\u{FFFD}")))
    }

    @Test("ESC timeout does not interfere with complete sequences")
    func testTimeoutDoesNotInterfereWithComplete() {
        let clock = TestInputClock()
        let pipe = InputPipeline(clock: clock, escapeTimeoutNanoseconds: 50_000_000)
        // ESC x in one feed → complete escape sequence, no timer needed
        let events = pipe.feed([0x1B, 0x78])
        #expect(events == [KeyEvent(key: .character("x"), modifiers: .alt)])

        // No pending timeout
        clock.advance(by: 100_000_000)
        let e2 = pipe.tick()
        #expect(e2.isEmpty)
    }
}

