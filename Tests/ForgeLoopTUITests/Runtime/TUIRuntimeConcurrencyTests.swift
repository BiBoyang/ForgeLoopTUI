import Foundation
import Testing
@testable import ForgeLoopTUI

/// Regression tests for `TUI`'s `@unchecked Sendable` contract: concurrent
/// render passes must be fully serialized (state swap + output assembly +
/// `terminal.write`), and `diagnosticsHandler` access must be lock-protected.
/// Best exercised under `--sanitize=thread`.
@Suite("TUI Concurrency")
struct TUIRuntimeConcurrencyTests {

    /// Thread-safe sink for captured terminal output.
    private final class OutputSink: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var writes: [String] = []

        func append(_ text: String) {
            lock.lock()
            writes.append(text)
            lock.unlock()
        }
    }

    @Test("concurrent renders never crash and always produce output")
    func testConcurrentRendersAreSerialized() {
        let sink = OutputSink()
        let tui = TUI(isTTY: true, terminalWidth: 80, terminalHeight: 100) { text in
            sink.append(text)
        }

        let lanes = 8
        let iterations = 100
        DispatchQueue.concurrentPerform(iterations: lanes) { lane in
            for i in 0..<iterations {
                // Ever-changing content guarantees every render pass emits.
                tui.render(
                    committed: ["lane \(lane) header \(i)"],
                    live: ["lane \(lane) live \(i)"],
                    cursorOffset: 0
                )
            }
        }

        // Every render with changed content produces exactly one write.
        #expect(sink.writes.count == lanes * iterations)
    }

    @Test("concurrent cursorPlacement renders keep placement undo intact")
    func testConcurrentCursorPlacementRenders() {
        let sink = OutputSink()
        let tui = TUI(
            isTTY: true,
            terminalWidth: 80,
            terminalHeight: 100,
            cursorPositioningMode: .marker
        ) { text in
            sink.append(text)
        }

        let lanes = 8
        let iterations = 50
        DispatchQueue.concurrentPerform(iterations: lanes) { lane in
            for i in 0..<iterations {
                tui.render(
                    committed: ["c\(lane)-\(i)"],
                    live: ["l\(lane)-\(i)"],
                    cursorPlacement: CursorPlacement(up: 0, offset: 1)
                )
            }
        }

        // Each placement render emits a content write plus a placement write.
        #expect(sink.writes.count == lanes * iterations * 2)
        // Every placement write contains a CHA (column absolute) sequence;
        // a lost/garbled undo would surface as a missing or malformed write.
        let placementWrites = sink.writes.filter { $0.contains("\u{1B}[") && !$0.contains("\u{1B}[2K") }
        #expect(placementWrites.allSatisfy { $0.contains("G") })
    }

    @Test("diagnosticsHandler concurrent set/read during renders is race-free")
    func testDiagnosticsHandlerConcurrentAccess() {
        let sink = OutputSink()
        let tui = TUI(isTTY: true, terminalWidth: 80, terminalHeight: 100) { text in
            sink.append(text)
        }

        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var value = 0
            func increment() {
                lock.lock()
                value += 1
                lock.unlock()
            }
        }
        let counter = Counter()

        DispatchQueue.concurrentPerform(iterations: 4) { lane in
            switch lane {
            case 0, 1:
                // Writer lanes: alternately set and clear the handler.
                for _ in 0..<200 {
                    tui.diagnosticsHandler = { _ in counter.increment() }
                    tui.diagnosticsHandler = nil
                }
            default:
                // Render lanes: invoke handler lookups through render passes.
                for i in 0..<200 {
                    tui.requestRender(lines: ["lane \(lane) frame \(i)"], cursorOffset: 0)
                }
            }
        }

        // No crash and no torn handler invocation is the assertion; sanity:
        // renders did emit output.
        #expect(!sink.writes.isEmpty)
    }

    @Test("concurrent resize, renders, and dims reads are race-free")
    func testConcurrentResizeAndDimsReads() {
        let sink = OutputSink()
        let tui = TUI(isTTY: true, terminalWidth: 80, terminalHeight: 100) { text in
            sink.append(text)
        }

        DispatchQueue.concurrentPerform(iterations: 4) { lane in
            switch lane {
            case 0:
                // Resize lane: width and height churn together.
                for i in 0..<200 {
                    tui.updateTerminalSize(width: 60 + (i % 40), height: 80 + (i % 20))
                }
            case 1:
                // Render lane: reads dims through physical-row math.
                for i in 0..<200 {
                    tui.render(
                        committed: ["lane-1 committed \(i)"],
                        live: ["lane-1 live \(i)"],
                        cursorOffset: 0
                    )
                }
            case 2:
                // Dims-read lane: direct public getter access.
                for _ in 0..<200 {
                    _ = tui.terminalWidth
                    _ = tui.terminalHeight
                }
            default:
                // Mixed render + resize lane: worst-case interleaving.
                for i in 0..<100 {
                    tui.requestRender(lines: ["lane-3 frame \(i)"], cursorOffset: 0)
                    tui.updateTerminalSize(width: 70 + (i % 30), height: 90)
                }
            }
        }

        // No crash / no TSan report is the assertion; sanity: renders and
        // the final dims value are observable.
        #expect(!sink.writes.isEmpty)
        #expect(tui.terminalWidth > 0)
        #expect(tui.terminalHeight > 0)
    }
}
