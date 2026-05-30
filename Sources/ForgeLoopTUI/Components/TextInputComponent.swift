/// A component that renders a single-line text input prompt.
///
/// The component is stateless; the caller is responsible for
/// tracking the current input value and cursor position.
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
