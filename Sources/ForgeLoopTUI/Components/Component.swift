import Foundation

/// A renderable UI primitive.
///
/// Given a terminal width, a component produces logical lines.
/// Height is implicit in the line count.
@available(*, deprecated, message: "The declarative component tree is an unverified design with no known production consumers and will be removed in 2.0. Render via TUI.render(committed:live:…) or the TranscriptRenderer/CoreRenderEvent event model instead.")
public protocol Component: Sendable {
    func render(width: Int) -> [String]
}

/// Type-erased wrapper for heterogeneous component collections.
///
/// Intentionally public: required by `VStack.components`, `FrameComposer.init`,
/// and the `@ComponentBuilder` result builder, which all use `[AnyComponent]`
/// in their public API surface. Without a public type-erased wrapper,
/// consumers cannot construct component lists programmatically.
@available(*, deprecated, message: "The declarative component tree is an unverified design with no known production consumers and will be removed in 2.0. Render via TUI.render(committed:live:…) or the TranscriptRenderer/CoreRenderEvent event model instead.")
public struct AnyComponent: Component, @unchecked Sendable {
    private let _render: @Sendable (Int) -> [String]

    public init<C: Component>(_ component: C) {
        _render = { component.render(width: $0) }
    }

    public func render(width: Int) -> [String] {
        _render(width)
    }
}
