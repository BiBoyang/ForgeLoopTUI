extension TUI {
    /// Convenience: render a pre-composed frame.
    public func render(frame: ComposedFrame) {
        if let placement = frame.cursorPlacement {
            render(committed: frame.committed, live: frame.live, cursorPlacement: placement)
        } else {
            render(committed: frame.committed, live: frame.live, cursorOffset: frame.cursorOffset)
        }
    }
}
