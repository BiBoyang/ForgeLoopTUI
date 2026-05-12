import Foundation

/// Adapts a single ``HybridRenderState`` into both terminal and AppKit projections.
///
/// The adapter is pure: it does not retain state across calls. Each invocation
/// derives the two downstream representations from the source state independently.
///
/// ## Data flow
///
/// ```
/// HybridRenderState
///        │
///        ├──► TerminalRenderState ──► ScreenLayoutRenderer ──► ComposedFrame
///        │
///        └──► AppKitPanelState  ───► (AppKit consumer observes & renders)
/// ```
///
/// ## Constraints
///
/// - Terminal path continues to use ``ScreenLayoutRenderer`` + ``ComposedFrame``.
/// - AppKit path provides only a data model; no NSView controls are created here.
/// - No dual-write: the source state is read-only for the adapter.
public struct HybridRenderAdapter: Sendable {

    public init() {}

    // MARK: - Terminal Projection

    /// Derives a ``TerminalRenderState`` from the shared source.
    ///
    /// - Parameters:
    ///   - state: The source of truth.
    ///   - config: Terminal geometry and flags.
    ///   - cursorOffset: Optional cursor offset for the live region.
    /// - Returns: A terminal projection ready for ``ScreenLayoutRenderer``.
    public func terminalProjection(
        of state: HybridRenderState,
        config: ScreenLayoutConfig,
        cursorOffset: Int? = nil
    ) -> TerminalRenderState {
        let layout = ScreenLayout(
            header: state.headerLines,
            transcript: state.transcriptLines,
            queue: state.queueLines,
            status: state.statusLines,
            input: state.inputLines,
            pinnedTranscriptRange: state.pinnedTranscriptRange
        )
        return TerminalRenderState(
            layout: layout,
            config: config,
            cursorOffset: cursorOffset
        )
    }

    /// Convenience: renders the terminal projection directly into a ``ComposedFrame``.
    ///
    /// - Parameters:
    ///   - state: The source of truth.
    ///   - config: Terminal geometry and flags.
    ///   - cursorOffset: Optional cursor offset.
    /// - Returns: A composed frame ready for `TUI.render(frame:)`.
    public func renderTerminal(
        state: HybridRenderState,
        config: ScreenLayoutConfig,
        cursorOffset: Int? = nil
    ) -> ComposedFrame {
        // 防御：零或负终端尺寸不崩溃，返回空帧
        guard config.terminalWidth > 0, config.terminalHeight > 0 else {
            return ComposedFrame(committed: [], live: [], cursorOffset: nil)
        }

        let projection = terminalProjection(of: state, config: config, cursorOffset: cursorOffset)
        return ScreenLayoutRenderer().render(
            layout: projection.layout,
            config: projection.config,
            cursorOffset: projection.cursorOffset
        )
    }

    // MARK: - AppKit Projection

    /// Derives an ``AppKitPanelState`` from the shared source.
    ///
    /// - Parameter state: The source of truth.
    /// - Returns: An AppKit data model containing the same logical content
    ///   reorganised for native panel consumption.
    public func appKitProjection(of state: HybridRenderState) -> AppKitPanelState {
        AppKitPanelState(
            transcriptLines: state.transcriptLines,
            inputLines: state.inputLines,
            statusLines: state.statusLines,
            queueLines: state.queueLines,
            // 降级：panelMeta 为 nil 时使用空值默认，保证 AppKit 投影总是可用的
            meta: state.panelMeta ?? PanelMeta(),
            inputFocused: !state.inputLines.isEmpty
        )
    }

    // MARK: - Dual Projection

    /// Produces both projections in a single call.
    ///
    /// This is the primary "demo" entry point: given one state, you get
    /// both a terminal frame and an AppKit panel model.
    ///
    /// - Parameters:
    ///   - state: The source of truth.
    ///   - config: Terminal geometry and flags.
    ///   - cursorOffset: Optional cursor offset.
    /// - Returns: A tuple of `(terminalFrame, appKitPanel)`.
    public func renderBoth(
        state: HybridRenderState,
        config: ScreenLayoutConfig,
        cursorOffset: Int? = nil
    ) -> (terminal: ComposedFrame, appKit: AppKitPanelState) {
        let terminalFrame = renderTerminal(
            state: state,
            config: config,
            cursorOffset: cursorOffset
        )
        let appKitPanel = appKitProjection(of: state)
        return (terminalFrame, appKitPanel)
    }
}
