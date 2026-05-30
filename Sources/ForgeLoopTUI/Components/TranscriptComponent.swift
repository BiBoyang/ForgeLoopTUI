/// Wraps a `TranscriptRenderer` as a `Component`.
///
/// The component renders the current transcript lines every time
/// `render(width:)` is called.
public struct TranscriptComponent: Component {
    private let getLines: @Sendable () -> [String]

    public init(getLines: @escaping @Sendable () -> [String]) {
        self.getLines = getLines
    }

    public func render(width: Int) -> [String] {
        getLines()
    }
}
