import Foundation

/// Generic render event (chat-semantics-free).
///
/// Used by the `ForgeLoopTUI` Core layer; not bound to any business model.
/// Chat semantics are injected through the Adapter layer.
public enum CoreRenderEvent: Sendable, Equatable {
    /// Insert static text lines (not updatable).
    case insert(lines: [String])

    /// Begin an updatable content block.
    ///
    /// Block events are single-active-block: only one block may be open at a
    /// time. A `blockStart` arriving while another block is still open
    /// implicitly finalizes the previous block (its streamed content is kept
    /// as-is) before the new block begins.
    case blockStart(id: String)

    /// Update the lines of a content block.
    ///
    /// The `id` must match the currently open block's id; mismatched updates
    /// are ignored. An update with no preceding `blockStart` implicitly opens
    /// a block adopting that `id`.
    case blockUpdate(id: String, lines: [String])

    /// End a content block, appending an optional footer (e.g. an error message).
    ///
    /// The `id` must match the currently open block's id; mismatched ends are
    /// ignored.
    case blockEnd(id: String, lines: [String], footer: String?)

    /// Cancel an in-progress content block (e.g. user interruption).
    /// Unlike `blockEnd`: the streamed content is discarded; only the
    /// cancellation marker is kept.
    ///
    /// The `id` must match the currently open block's id; mismatched cancels
    /// are ignored.
    case blockCancel(id: String)

    /// Model thinking/reasoning content (rendered distinctly from regular assistant text).
    /// - content: the currently accumulated thinking text
    /// - isFinal: whether this is the final chunk (thinking has ended)
    case thinking(content: String, isFinal: Bool)

    /// Begin a tracked operation.
    /// - header: the operation title line (e.g. "● toolName(args)")
    /// - status: the initial status line (e.g. "⎿ running...")
    case operationStart(id: String, header: String, status: String)

    /// End an operation, replacing the status line with the result.
    /// - result: optional result text (e.g. a summary)
    case operationEnd(id: String, isError: Bool, result: String?)

    /// Notification message (auto-collapsed).
    case notification(text: String)
}
