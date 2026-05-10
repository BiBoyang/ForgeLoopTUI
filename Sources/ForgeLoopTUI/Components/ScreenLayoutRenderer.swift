import Foundation

public struct ScreenLayoutRenderer: Sendable {
    public init() {}

    public func render(
        layout: ScreenLayout,
        config: ScreenLayoutConfig,
        cursorOffset: Int? = nil
    ) -> ComposedFrame {
        var lines: [String] = []

        if config.showHeader && !layout.header.isEmpty {
            lines.append(contentsOf: layout.header)
        }

        lines.append(contentsOf: layout.transcript)

        if !layout.queue.isEmpty {
            lines.append("")
            lines.append(contentsOf: layout.queue)
        }

        if !layout.status.isEmpty {
            lines.append("")
            lines.append(contentsOf: layout.status)
        }

        if !layout.input.isEmpty {
            lines.append("")
            lines.append(contentsOf: layout.input)
        }

        // 行为对齐旧实现：全部作为 committed，live 先置空
        return ComposedFrame(
            committed: lines,
            live: [],
            cursorOffset: cursorOffset
        )
    }
}
