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

// MARK: - Panel Metadata Protocol

/// A protocol for panel metadata providers.
///
/// The AppKit app side implements this protocol, and the Bridge layer consumes
/// metadata through it without needing to know the concrete source
/// (window title, bindings, user preferences, etc.).
///
/// ## Example
/// ```swift
/// struct MyPanelInfo: PanelMetadataProviding {
///     var title: String { "My AI Session" }
///     var summary: String { "12 messages" }
///     var statusBadge: String { "Streaming" }
///     var isActive: Bool { true }
///     var subtitle: String? { "gpt-4o · 3.2k tokens" }
/// }
/// ```
public protocol PanelMetadataProviding: Sendable {
    var title: String { get }
    var summary: String { get }
    var statusBadge: String { get }
    var isActive: Bool { get }
    var subtitle: String? { get }
    var accessoryBadge: String? { get }
}

extension PanelMetadataProviding {
    public var subtitle: String? { nil }
    public var accessoryBadge: String? { nil }
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

    /// Subtitle (contextual info such as model name, token count, etc.)
    public var subtitle: String?

    /// Accessory badge (labels such as "Beta", "Pro", etc.)
    public var accessoryBadge: String?

    public init(
        title: String = "",
        summary: String = "",
        statusBadge: String = "",
        isActive: Bool = false,
        subtitle: String? = nil,
        accessoryBadge: String? = nil
    ) {
        self.title = title
        self.summary = summary
        self.statusBadge = statusBadge
        self.isActive = isActive
        self.subtitle = subtitle
        self.accessoryBadge = accessoryBadge
    }
}

extension PanelMeta: PanelMetadataProviding {}

// MARK: - Panel Metadata Bridge

extension PanelMeta {
    /// Creates a `PanelMeta` from any `PanelMetadataProviding` provider.
    ///
    /// This is the bridging entry point from the protocol to the concrete value type:
    /// after the app side implements the protocol, this initializer produces a
    /// `PanelMeta` that the Bridge layer can consume.
    public init<P: PanelMetadataProviding>(_ provider: P) {
        self.init(
            title: provider.title,
            summary: provider.summary,
            statusBadge: provider.statusBadge,
            isActive: provider.isActive,
            subtitle: provider.subtitle,
            accessoryBadge: provider.accessoryBadge
        )
    }
}

extension HybridRenderState {
    /// Updates the panel metadata from a `PanelMetadataProviding` provider.
    public mutating func updatePanelMeta<P: PanelMetadataProviding>(from provider: P) {
        panelMeta = PanelMeta(provider)
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
