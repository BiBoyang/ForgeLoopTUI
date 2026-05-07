extension TUI {
    /// Convenience: render a pre-composed frame.
    public func render(frame: ComposedFrame) {
        render(committed: frame.committed, live: frame.live, cursorOffset: frame.cursorOffset)
    }
}
