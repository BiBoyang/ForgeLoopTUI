import Foundation
import Testing
@testable import ForgeLoopTUI

/// Contract tests for `RenderLoop` (audit P2-2): the coalescing render
/// scheduler that ForgeLoop drives directly and that previously had zero
/// coverage. Covers the submit/flush/stop lifecycle, in-tick frame
/// coalescing, and race stress against the `@unchecked Sendable`
/// implementation. Best exercised under
/// `swift test --sanitize=thread --filter RenderLoopTests`.
///
/// Note: `RenderLoop`'s timer hops to `@MainActor`, and the `.immediate`
/// flush runs inline on the submitting caller's context — both are pinned
/// by tests below.
@Suite("RenderLoop")
struct RenderLoopTests {

    /// Thread-safe sink capturing rendered frames.
    private final class FrameSink: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var frames: [[String]] = []

        func append(_ frame: [String]) {
            lock.lock()
            frames.append(frame)
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return frames.count
        }
    }

    /// Polls `condition` until it holds or the timeout elapses.
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 3_000_000_000,
        pollIntervalNanoseconds: UInt64 = 5_000_000,
        _ condition: () -> Bool
    ) async -> Bool {
        var elapsed: UInt64 = 0
        while elapsed < timeoutNanoseconds {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            elapsed += pollIntervalNanoseconds
        }
        return condition()
    }

    // MARK: - Lifecycle: submit / flush / stop

    @Test(".immediate submit renders synchronously on the caller context")
    func immediateSubmitRendersSynchronously() {
        let sink = FrameSink()
        let loop = RenderLoop(tickIntervalNanoseconds: 50_000_000) { sink.append($0) }

        loop.submit(frame: ["alpha", "beta"], priority: .immediate)

        // The .immediate flush runs inline before `submit` returns.
        #expect(sink.frames == [["alpha", "beta"]])
        loop.stop()
    }

    @Test(".normal submit renders on a tick, never synchronously, exactly once")
    func normalSubmitRendersAfterTick() async {
        let sink = FrameSink()
        let loop = RenderLoop(tickIntervalNanoseconds: 50_000_000) { sink.append($0) }

        loop.submit(frame: ["f1"])
        #expect(sink.count == 0)

        let rendered = await waitUntil { sink.count == 1 }
        #expect(rendered)
        #expect(sink.frames.first == ["f1"])

        // After an idle flush the timer stops: no repeat renders.
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(sink.count == 1)
        loop.stop()
    }

    @Test("stop discards the pending frame and silences the timer")
    func stopDiscardsPendingFrame() async {
        let sink = FrameSink()
        let loop = RenderLoop(tickIntervalNanoseconds: 100_000_000) { sink.append($0) }

        loop.submit(frame: ["doomed"])
        loop.stop()

        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(sink.count == 0)
    }

    @Test("stop is idempotent and submissions after stop are ignored")
    func stopIsIdempotentAndSubmitAfterStopIgnored() async {
        let sink = FrameSink()
        let loop = RenderLoop(tickIntervalNanoseconds: 100_000_000) { sink.append($0) }

        loop.stop()
        loop.stop()
        loop.submit(frame: ["ignored-normal"])
        loop.submit(frame: ["ignored-immediate"], priority: .immediate)

        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(sink.count == 0)
    }

    @Test("the timer restarts for a new submission after an idle flush")
    func timerRestartsAfterIdleFlush() async {
        let sink = FrameSink()
        let loop = RenderLoop(tickIntervalNanoseconds: 50_000_000) { sink.append($0) }

        loop.submit(frame: ["first"])
        let first = await waitUntil { sink.count == 1 }
        #expect(first)

        // The queue is drained and the timer stopped; a new submission must
        // restart it and deliver exactly one more render.
        loop.submit(frame: ["second"])
        let second = await waitUntil { sink.count == 2 }
        #expect(second)

        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(sink.frames == [["first"], ["second"]])
        loop.stop()
    }

    // MARK: - Coalescing

    @Test("multiple .normal submits within one tick coalesce to the last frame")
    func normalSubmitsCoalesceToLastFrame() async {
        let sink = FrameSink()
        let loop = RenderLoop(tickIntervalNanoseconds: 100_000_000) { sink.append($0) }

        loop.submit(frame: ["f1"])
        loop.submit(frame: ["f2"])
        loop.submit(frame: ["f3"])

        let rendered = await waitUntil { sink.count == 1 }
        #expect(rendered)

        // One tick rendered the last frame only; the timer then went idle.
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(sink.frames == [["f3"]])
        loop.stop()
    }

    @Test(".immediate flushes the latest pending frame and supersedes the pending tick")
    func immediateFlushSupersedesPendingFrame() async {
        let sink = FrameSink()
        let loop = RenderLoop(tickIntervalNanoseconds: 100_000_000) { sink.append($0) }

        loop.submit(frame: ["stale"])
        loop.submit(frame: ["fresh"], priority: .immediate)

        // The inline flush consumed the pending frame and idled the timer.
        #expect(sink.frames == [["fresh"]])
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(sink.count == 1)
        loop.stop()
    }

    // MARK: - Race stress

    @Test("concurrent .immediate submits preserve frame integrity")
    func concurrentImmediateSubmitsPreserveIntegrity() {
        let sink = FrameSink()
        let loop = RenderLoop(tickIntervalNanoseconds: 10_000_000) { sink.append($0) }

        let lanes = 8
        let iterations = 200
        DispatchQueue.concurrentPerform(iterations: lanes) { lane in
            for i in 0..<iterations {
                loop.submit(frame: ["L\(lane)-\(i)"], priority: .immediate)
            }
        }
        loop.stop()

        // Each flush consumes at most one stored frame, so renders never
        // exceed submissions, and every rendered frame arrives intact.
        #expect(sink.count > 0)
        #expect(sink.count <= lanes * iterations)
        #expect(sink.frames.allSatisfy { frame in
            frame.count == 1 && frame[0].hasPrefix("L") && frame[0].contains("-")
        })
    }

    @Test("concurrent .normal submits coalesce and the timer goes idle")
    func concurrentNormalSubmitsStress() async {
        let sink = FrameSink()
        let loop = RenderLoop(tickIntervalNanoseconds: 10_000_000) { sink.append($0) }

        let lanes = 8
        DispatchQueue.concurrentPerform(iterations: lanes) { lane in
            for i in 0..<100 {
                loop.submit(frame: ["n\(lane)-\(i)"])
            }
        }

        let rendered = await waitUntil { sink.count >= 1 }
        #expect(rendered)

        // After the producers finish, the queue drains and the timer stops.
        try? await Task.sleep(nanoseconds: 200_000_000)
        let quiesced = sink.count
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(sink.count == quiesced)
        #expect(sink.frames.allSatisfy { $0.count == 1 && $0[0].hasPrefix("n") })
        loop.stop()
    }

    @Test("stop racing with in-flight submits is race-free")
    func stopRacingWithSubmits() async {
        let sink = FrameSink()
        let loop = RenderLoop(tickIntervalNanoseconds: 5_000_000) { sink.append($0) }

        await withTaskGroup(of: Void.self) { group in
            for lane in 0..<4 {
                group.addTask {
                    for i in 0..<200 {
                        if lane % 2 == 0 {
                            loop.submit(frame: ["n\(lane)-\(i)"])
                        } else {
                            loop.submit(frame: ["i\(lane)-\(i)"], priority: .immediate)
                        }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 20_000_000)
                loop.stop()
            }
        }

        // The grace period absorbs renders already in flight when stop
        // landed; after that no new render can be initiated (stopped
        // submissions never store a frame, and the timer is cancelled).
        try? await Task.sleep(nanoseconds: 100_000_000)
        let quiesced = sink.count
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(sink.count == quiesced)
        #expect(sink.frames.allSatisfy { $0.count == 1 })
    }
}
