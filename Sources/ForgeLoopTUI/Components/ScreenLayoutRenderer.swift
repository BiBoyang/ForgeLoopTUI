import Foundation

/// Renders a ``ScreenLayout`` into a ``ComposedFrame`` with a minimal live-region policy.
///
/// Live-region policy (stable, testable, and visually neutral):
/// - **Live** = the final `input` lines (if any). Input is inherently transient and
///   may change on every keystroke, so it is the smallest, most stable candidate for
///   the live region.
/// - **Committed** = everything else (`header`, `transcript`, `queue`, `status`,
///   plus divider blank lines). These lines change far less frequently and are safe
///   to treat as stable history.
///
/// This keeps the visible text order identical to the old all-committed path while
/// giving the downstream runtime a real live region to diff.
public struct ScreenLayoutRenderer: Sendable {
    public init() {}

    public func render(
        layout: ScreenLayout,
        config: ScreenLayoutConfig,
        cursorOffset: Int? = nil
    ) -> ComposedFrame {
        var committed: [String] = []

        if config.showHeader && !layout.header.isEmpty {
            committed.append(contentsOf: layout.header)
        }

        committed.append(contentsOf: layout.transcript)

        if !layout.queue.isEmpty {
            committed.append("")
            committed.append(contentsOf: layout.queue)
        }

        if !layout.status.isEmpty {
            committed.append("")
            committed.append(contentsOf: layout.status)
        }

        // Input is the live region (minimal stable rule).
        let live: [String]
        if layout.input.isEmpty {
            live = []
        } else {
            // Prepend a divider blank line when there is preceding committed content.
            if committed.isEmpty {
                live = layout.input
            } else {
                live = [""] + layout.input
            }
        }

        return ComposedFrame(
            committed: committed,
            live: live,
            cursorOffset: cursorOffset
        )
    }
}
