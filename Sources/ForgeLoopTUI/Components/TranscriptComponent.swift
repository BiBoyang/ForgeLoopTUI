/// Wraps a `TranscriptRenderer` as a `Component`.
///
/// The component renders the current transcript lines every time
/// `render(width:)` is called.
@available(*, deprecated, message: "The declarative component tree is an unverified design with no known production consumers and will be removed in 2.0. Render via TUI.render(committed:live:…) or the TranscriptRenderer/CoreRenderEvent event model instead.")
public struct TranscriptComponent: Component {
    private let getLines: @Sendable () -> [String]

    public init(getLines: @escaping @Sendable () -> [String]) {
        self.getLines = getLines
    }

    public func render(width: Int) -> [String] {
        getLines()
    }
}
