import Foundation
@testable import ForgeLoopTUI

// MARK: - OutputSpy

/// Thread-safe collector of all text written through a `FrameWriter` closure.
/// Used across TUITests, CommittedLiveRenderTests, and InputLayoutReplayTests.
final class OutputSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var _outputs: [String] = []

    var outputs: [String] { lock.withLock { _outputs } }
    var last: String? { lock.withLock { _outputs.last } }

    lazy var writer: FrameWriter = { [weak self] text in
        self?.lock.withLock { self?._outputs.append(text) }
    }
}

// MARK: - TestInputClock

/// Deterministic clock for testing time-dependent input behavior
/// (escape timeout, key resolver chord timeout).
final class TestInputClock: InputClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: UInt64 = 0

    func now() -> UInt64 {
        lock.withLock { _now }
    }

    func advance(by nanoseconds: UInt64) {
        lock.withLock { _now += nanoseconds }
    }
}
