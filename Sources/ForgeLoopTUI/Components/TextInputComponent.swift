/// A component that renders a single-line text input prompt.
///
/// The component is stateless; the caller is responsible for
/// tracking the current input value and cursor position.
@available(*, deprecated, message: "The declarative component tree is an unverified design with no known production consumers and will be removed in 2.0. Render via TUI.render(committed:live:…) or the TranscriptRenderer/CoreRenderEvent event model instead.")
public struct TextInputComponent: Component {
    public let prompt: String
    public let value: String

    public init(prompt: String, value: String = "") {
        self.prompt = prompt
        self.value = value
    }

    public func render(width: Int) -> [String] {
        [prompt + value]
    }
}
