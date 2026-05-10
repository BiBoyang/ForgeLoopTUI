import Foundation
import ForgeLoopTUI

/// 可视化预览任意 Component 的渲染结果。
///
/// 用法：在 Demo 中调用 `preview(component, width: 60, label: "My Component")`
func preview(_ component: some Component, width: Int = 60, height: Int = 12, label: String = "Preview") {
    let tty = VirtualTerminal(width: width, height: height)
    let tui = TUI(strategy: .legacyAbsolute, isTTY: true, terminal: tty)

    let composer = FrameComposer(
        committed: [AnyComponent(component)],
        layoutBudget: LayoutBudget(maxRows: height, overflowMarker: "…")
    )
    tui.render(frame: composer.render(width: width))

    let header = "┌─ \(label) "
    let pad = width + 3 - header.count
    print("\n" + header + String(repeating: "─", count: max(0, pad)) + "┐")
    for line in tty.screenLines {
        print("│ \(line) │")
    }
    print("└" + String(repeating: "─", count: width + 2) + "┘")
}

/// 预览一个已渲染好的 ComposedFrame。
func previewFrame(_ frame: ComposedFrame, width: Int, height: Int, label: String = "Frame") {
    let tty = VirtualTerminal(width: width, height: height)
    let tui = TUI(strategy: .legacyAbsolute, isTTY: true, terminal: tty)
    tui.render(frame: frame)

    let header = "┌─ \(label) "
    let pad = width + 3 - header.count
    print("\n" + header + String(repeating: "─", count: max(0, pad)) + "┐")
    for line in tty.screenLines {
        print("│ \(line) │")
    }
    print("└" + String(repeating: "─", count: width + 2) + "┘")
}
