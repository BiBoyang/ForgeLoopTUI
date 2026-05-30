import Foundation

/// Vertically stacks components with optional fixed spacing.
///
/// Spacing produces empty lines *between* adjacent components; no
/// trailing or leading blank lines are added.
public struct VStack: Component {
    public let components: [AnyComponent]
    public let spacing: Int

    public init<C: Component>(spacing: Int = 0, @ComponentBuilder _ content: () -> C) {
        let root = content()
        if let stack = root as? VStack {
            self.components = stack.components
            self.spacing = max(0, spacing)
        } else {
            self.components = [AnyComponent(root)]
            self.spacing = max(0, spacing)
        }
    }

    public init(components: [AnyComponent], spacing: Int = 0) {
        self.components = components
        self.spacing = max(0, spacing)
    }

    public func render(width: Int) -> [String] {
        var lines: [String] = []
        var isFirst = true
        for component in components {
            if !isFirst && spacing > 0 {
                lines.append(contentsOf: Array(repeating: "", count: spacing))
            }
            isFirst = false
            lines.append(contentsOf: component.render(width: width))
        }
        return lines
    }
}

// MARK: - ComponentBuilder

/// Declarative DSL for composing nested component trees.
///
/// Uses `buildPartialBlock` so there is no fixed limit on the number of
/// sibling components.  All builder methods return `VStack` so `if` /
/// `if-else` branches compile without type mismatches, and a nested
/// `VStack { … }` is detected and flattened by the outer `VStack.init`.
@resultBuilder
public enum ComponentBuilder {
    public static func buildExpression<C: Component>(_ component: C) -> VStack {
        VStack(components: [AnyComponent(component)], spacing: 0)
    }

    public static func buildPartialBlock(first component: VStack) -> VStack {
        component
    }

    public static func buildPartialBlock(accumulated: VStack, next: VStack) -> VStack {
        VStack(components: accumulated.components + next.components, spacing: 0)
    }

    public static func buildOptional(_ component: VStack?) -> VStack {
        component ?? VStack(components: [], spacing: 0)
    }

    public static func buildEither(first component: VStack) -> VStack {
        component
    }

    public static func buildEither(second component: VStack) -> VStack {
        component
    }

    public static func buildArray(_ components: [VStack]) -> VStack {
        VStack(components: components.flatMap { $0.components }, spacing: 0)
    }
}

/// Zero-height component used for `buildOptional` fallback.
struct EmptyComponent: Component {
    public init() {}
    public func render(width: Int) -> [String] { [] }
}
