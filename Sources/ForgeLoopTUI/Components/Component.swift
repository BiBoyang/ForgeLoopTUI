import Foundation

/// A renderable UI primitive.
///
/// Given a terminal width, a component produces logical lines.
/// Height is implicit in the line count.
public protocol Component: Sendable {
    func render(width: Int) -> [String]
}

/// Type-erased wrapper for heterogeneous component collections.
public struct AnyComponent: Component, @unchecked Sendable {
    private let _render: @Sendable (Int) -> [String]

    public init<C: Component>(_ component: C) {
        _render = { component.render(width: $0) }
    }

    public func render(width: Int) -> [String] {
        _render(width)
    }
}
