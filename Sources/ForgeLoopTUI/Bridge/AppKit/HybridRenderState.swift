import Foundation

// MARK: - Shared Source State

/// The single source of truth for hybrid rendering.
///
/// `HybridRenderState` holds generic UI state with no terminal-specific
/// or AppKit-specific assumptions. It is projected into two downstream
/// representations:
///
/// - ``TerminalRenderState`` → drives `ScreenLayoutRenderer` → `ComposedFrame`
/// - ``AppKitPanelState``    → drives an AppKit subview (data-only, no NSView logic)
///
/// Both projections are read-only derivations. No dual-write is permitted.
public struct HybridRenderState: Sendable, Equatable {
    public var headerLines: [String]
    public var transcriptLines: [String]
    public var queueLines: [String]
    public var statusLines: [String]
    public var inputLines: [String]

    /// Transcript range that must be preserved intact (e.g. streaming block).
    public var pinnedTranscriptRange: Range<Int>?

    /// Optional panel metadata for AppKit projection.
    public var panelMeta: PanelMeta?

    public init(
        headerLines: [String] = [],
        transcriptLines: [String] = [],
        queueLines: [String] = [],
        statusLines: [String] = [],
        inputLines: [String] = [],
        pinnedTranscriptRange: Range<Int>? = nil,
        panelMeta: PanelMeta? = nil
    ) {
        self.headerLines = headerLines
        self.transcriptLines = transcriptLines
        self.queueLines = queueLines
        self.statusLines = statusLines
        self.inputLines = inputLines
        self.pinnedTranscriptRange = pinnedTranscriptRange
        self.panelMeta = panelMeta
    }
}

// MARK: - Panel Metadata

/// AppKit-facing metadata extracted from the shared state.
///
/// Kept separate from `HybridRenderState` fields so that terminal-only
/// consumers can ignore it entirely.
public struct PanelMeta: Sendable, Equatable {
    /// Top-level title for the panel / window.
    public var title: String

    /// One-line summary (e.g. "3 messages · generating…").
    public var summary: String

    /// Human-readable status badge (e.g. "Ready", "Streaming").
    public var statusBadge: String

    /// Whether the panel should indicate activity (spinner, pulsating dot, etc).
    public var isActive: Bool

    public init(
        title: String = "",
        summary: String = "",
        statusBadge: String = "",
        isActive: Bool = false
    ) {
        self.title = title
        self.summary = summary
        self.statusBadge = statusBadge
        self.isActive = isActive
    }
}

// MARK: - Terminal Projection

/// A terminal-specific projection derived from ``HybridRenderState``.
///
/// This is a thin wrapper around `ScreenLayout` + `ScreenLayoutConfig`
/// so that the bridge layer can speak in its own vocabulary while
/// reusing the existing TUI renderer unchanged.
public struct TerminalRenderState: Sendable, Equatable {
    /// The layout model consumed by ``ScreenLayoutRenderer``.
    public var layout: ScreenLayout

    /// Terminal geometry and visibility flags.
    public var config: ScreenLayoutConfig

    /// Cursor offset relative to the live region.
    public var cursorOffset: Int?

    public init(
        layout: ScreenLayout,
        config: ScreenLayoutConfig,
        cursorOffset: Int? = nil
    ) {
        self.layout = layout
        self.config = config
        self.cursorOffset = cursorOffset
    }
}

// MARK: - AppKit Projection

/// An AppKit-specific projection derived from ``HybridRenderState``.
///
/// Contains only data — no `NSView` references, no Cocoa layout logic.
/// A real AppKit panel would observe this value and update its subviews.
public struct AppKitPanelState: Sendable, Equatable {
    /// Lines shown in the transcript / scroll-back area.
    public var transcriptLines: [String]

    /// Lines shown in the input composer area.
    public var inputLines: [String]

    /// Status / footer lines.
    public var statusLines: [String]

    /// Queue / pending items.
    public var queueLines: [String]

    /// Panel metadata (title, summary, badge, activity).
    public var meta: PanelMeta

    /// Whether the input area should be first-responder.
    public var inputFocused: Bool

    public init(
        transcriptLines: [String] = [],
        inputLines: [String] = [],
        statusLines: [String] = [],
        queueLines: [String] = [],
        meta: PanelMeta = PanelMeta(),
        inputFocused: Bool = false
    ) {
        self.transcriptLines = transcriptLines
        self.inputLines = inputLines
        self.statusLines = statusLines
        self.queueLines = queueLines
        self.meta = meta
        self.inputFocused = inputFocused
    }
}
