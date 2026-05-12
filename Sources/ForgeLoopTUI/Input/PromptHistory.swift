/// 最小输入历史，支持上下键导航。
public struct PromptHistory: Sendable, Equatable {
    private var entries: [String] = []
    private var index: Int = -1  // -1 表示当前编辑态

    public init() {}

    public mutating func commit(_ text: String) {
        guard !text.isEmpty else { return }
        entries.insert(text, at: 0)
        index = -1
    }

    public mutating func prev() -> String? {
        guard index < entries.count - 1 else { return nil }
        index += 1
        return entries[index]
    }

    public mutating func next() -> String? {
        guard index >= 0 else { return nil }
        index -= 1
        return index >= 0 ? entries[index] : nil
    }

    public mutating func reset() {
        index = -1
    }

    public var isAtCurrent: Bool { index < 0 }
}
