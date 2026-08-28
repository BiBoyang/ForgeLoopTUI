/// A component that renders a selectable list with a cursor indicator.
@available(*, deprecated, message: "The declarative component tree is an unverified design with no known production consumers and will be removed in 2.0. Render via TUI.render(committed:live:…) or the TranscriptRenderer/CoreRenderEvent event model instead.")
public struct ListPickerComponent: Component {
    public let items: [String]
    public let selectedIndex: Int
    public let cursor: String

    public init(items: [String], selectedIndex: Int = 0, cursor: String = "> ") {
        self.items = items
        self.selectedIndex = selectedIndex
        self.cursor = cursor
    }

    public func render(width: Int) -> [String] {
        items.enumerated().map { index, item in
            let prefix = index == selectedIndex ? cursor : String(repeating: " ", count: cursor.count)
            return prefix + item
        }
    }
}
