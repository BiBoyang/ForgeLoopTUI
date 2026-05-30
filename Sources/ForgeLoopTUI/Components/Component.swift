import Foundation

/// A renderable UI primitive.
///
/// Given a terminal width, a component produces logical lines.
/// Height is implicit in the line count.
public protocol Component: Sendable {
    func render(width: Int) -> [String]
}

/// Type-erased wrapper for heterogeneous component collections.
///
/// Intentionally public: required by `VStack.components`, `FrameComposer.init`,
/// and the `@ComponentBuilder` result builder, which all use `[AnyComponent]`
/// in their public API surface. Without a public type-erased wrapper,
/// consumers cannot construct component lists programmatically.
public struct AnyComponent: Component, @unchecked Sendable {
    private let _render: @Sendable (Int) -> [String]

    public init<C: Component>(_ component: C) {
        _render = { component.render(width: $0) }
    }

    public func render(width: Int) -> [String] {
        _render(width)
    }
}
