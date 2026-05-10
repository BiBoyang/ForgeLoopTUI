import Foundation
import ForgeLoopTUI

/// 预览带 ANSI 颜色的组件输出（直接打印到 stdout，绕过 VirtualTerminal）。
func previewColor(_ lines: [String], width: Int, label: String = "Color Preview") {
    let header = "┌─ \(label) "
    let pad = width + 3 - header.count
    print("\n" + header + String(repeating: "─", count: max(0, pad)) + "┐")
    for line in lines {
        // 计算可见宽度（去掉 ANSI 序列）用于填充
        let visible = stripANSISequences(line)
        let fill = max(0, width - visible.count)
        print("│ \(line)\(String(repeating: " ", count: fill)) │")
    }
    print("└" + String(repeating: "─", count: width + 2) + "┘")
}

private func stripANSISequences(_ text: String) -> String {
    var result = ""
    var index = text.startIndex
    while index < text.endIndex {
        if text[index] == "\u{1B}" {
            // 跳过 ESC 序列
            var i = text.index(after: index)
            while i < text.endIndex && text[i] != "m" {
                i = text.index(after: i)
            }
            if i < text.endIndex {
                index = text.index(after: i)
                continue
            }
        }
        result.append(text[index])
        index = text.index(after: index)
    }
    return result
}

// MARK: - Styled Components

struct StyledMessageComponent: Component {
    let role: String
    let content: String

    func render(width: Int) -> [String] {
        let promptText = role == "user" ? "❯ " : "  "
        let prompt = role == "user"
            ? Style.prompt(promptText, mode: .ansi)
            : Style.dimmed(promptText, mode: .ansi)
        let body = role == "user"
            ? Style.user(content, mode: .ansi)
            : Style.header(content, mode: .ansi)
        return [prompt + body]
    }
}

struct StyledToolComponent: Component {
    let name: String
    let isRunning: Bool
    let isError: Bool
    let result: String?

    func render(width: Int) -> [String] {
        if let result = result {
            let styled = isError
                ? Style.error("❌ \(name) \(result)", mode: .ansi)
                : Style.success("✅ \(name) \(result)", mode: .ansi)
            return ["  " + styled]
        }
        if isRunning {
            return ["  " + Style.running("🔧 \(name) running...", mode: .ansi)]
        }
        return []
    }
}

// MARK: - Color Preview Examples

func runColorPreviews() {
    print("\n" + String(repeating: "═", count: 66))
    print("  COLOR PREVIEWS — run in a terminal that supports ANSI colors")
    print(String(repeating: "═", count: 66))

    let width = 50

    // User + Assistant conversation
    var lines: [String] = []
    lines.append(contentsOf: StyledMessageComponent(role: "user", content: "write fibonacci in swift").render(width: width))
    lines.append(contentsOf: StyledMessageComponent(role: "assistant", content: "Here's a simple Fibonacci:").render(width: width))
    lines.append("  " + Style.dimmed("func fib(_ n: Int) -> Int {", mode: .ansi))
    lines.append("  " + Style.dimmed("    return n <= 1 ? n : fib(n-1) + fib(n-2)", mode: .ansi))
    lines.append("  " + Style.dimmed("}", mode: .ansi))
    previewColor(lines, width: width, label: "Conversation")

    // Tool states
    var toolLines: [String] = []
    toolLines.append("  " + Style.running("🔧 read_file running...", mode: .ansi))
    previewColor(toolLines, width: width, label: "Tool Running")

    var toolDone: [String] = []
    toolDone.append("  " + Style.success("✅ read_file done", mode: .ansi))
    previewColor(toolDone, width: width, label: "Tool Success")

    var toolError: [String] = []
    toolError.append("  " + Style.error("❌ read_file failed: File not found", mode: .ansi))
    previewColor(toolError, width: width, label: "Tool Error")

    // Selection / Picker
    var pickerLines: [String] = []
    pickerLines.append("  " + Style.dimmed("Option A", mode: .ansi))
    pickerLines.append("  " + Style.selection("> Option B", mode: .ansi))
    pickerLines.append("  " + Style.dimmed("Option C", mode: .ansi))
    previewColor(pickerLines, width: width, label: "List Picker")

    // Budget overflow marker
    var budgetLines: [String] = []
    budgetLines.append("  " + Style.dimmed("old message 1", mode: .ansi))
    budgetLines.append("  " + Style.dimmed("old message 2", mode: .ansi))
    budgetLines.append("  " + Style.warning("…", mode: .ansi))
    budgetLines.append(contentsOf: StyledMessageComponent(role: "user", content: "latest message").render(width: width))
    previewColor(budgetLines, width: width, label: "Budget Clip")
}
