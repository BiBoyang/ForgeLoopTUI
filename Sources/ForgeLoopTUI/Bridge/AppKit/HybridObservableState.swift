import Foundation
import Observation

/// An observable wrapper around HybridRenderState.
///
/// Uses the macOS 14+ `@Observable` macro to provide reactive state tracking.
/// AppKit/SwiftUI views can respond automatically to state changes through
/// the standard observation pattern.
///
/// ## Usage (AppKit)
/// ```swift
/// let state = HybridObservableState()
/// withObservationTracking {
///     _ = state.transcriptLines  // start tracking
/// } onChange: {
///     // Update the UI when the state changes
/// }
/// ```
///
/// ## Threading Semantics
/// - This type is marked `@MainActor` and should be created and mutated on the main thread.
/// - As a UI state container, it is not safe to pass across actors; it deliberately
///   does not declare plain `Sendable`.
@available(macOS 14, *)
@Observable
@MainActor
public final class HybridObservableState {

    /// The underlying HybridRenderState
    public private(set) var state: HybridRenderState

    /// Convenience computed property used for Observation tracking
    public var transcriptLines: [String] { state.transcriptLines }
    public var inputLines: [String] { state.inputLines }
    public var statusLines: [String] { state.statusLines }
    public var queueLines: [String] { state.queueLines }
    public var headerLines: [String] { state.headerLines }
    public var panelMeta: PanelMeta { state.panelMeta ?? PanelMeta() }
    public var isInputFocused: Bool { !state.inputLines.isEmpty }

    public init(initialState: HybridRenderState = HybridRenderState()) {
        self.state = initialState
    }

    /// Replaces the entire state (notifies all observers)
    public func update(_ newState: HybridRenderState) {
        state = newState
    }

    /// Per-field updates (fine-grained; only notifies observers of the changed field)
    public func updateTranscript(_ lines: [String]) { state.transcriptLines = lines }
    public func updateInput(_ lines: [String]) { state.inputLines = lines }
    public func updateStatus(_ lines: [String]) { state.statusLines = lines }
    public func updateQueue(_ lines: [String]) { state.queueLines = lines }
    public func updateHeader(_ lines: [String]) { state.headerLines = lines }
    public func updateMeta(_ meta: PanelMeta) { state.panelMeta = meta }
    public func updatePinnedRange(_ range: Range<Int>?) { state.pinnedTranscriptRange = range }
}
