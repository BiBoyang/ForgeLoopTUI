import Foundation

/// Errors that the AppKit Bridge layer may produce.
@available(*, deprecated, message: "AppKitBridgeError is unused and will be removed in 2.0.0")
public enum AppKitBridgeError: Error, Sendable, Equatable {
    /// An input event could not be mapped to a KeyEvent (e.g. unknown specialKey, no characters and no keyCode match)
    case unmappableEvent(description: String)

    /// Logical conflict between fields of a HybridRenderState
    case inconsistentState(description: String)

    /// Invalid terminal size (width or height is zero or negative)
    case invalidTerminalSize(width: Int, height: Int)

    /// AppKit panel metadata is missing (panelMeta is nil and no default value is available)
    case missingPanelMetadata
}
