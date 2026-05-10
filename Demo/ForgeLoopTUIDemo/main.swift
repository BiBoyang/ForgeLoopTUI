import Foundation
import ForgeLoopTUI

@MainActor
final class Demo {
    let width = 60
    let height = 14
    var state = State()

    struct State {
        var messages: [(role: String, content: String)] = []
        var inputText = ""
        var liveResponse = ""
        var pendingTool: String?
        var toolResult: String?
        var isError = false
    }

    func run() {
        // ── 1. Empty ──
        scenario("1. Empty interface", delay: 0.3)

        // ── 2. Typing (char by char) ──
        animateTyping("write fibonacci in swift", delay: 0.03)
        scenario("2. User typing", delay: 0.5)

        // ── 3. Sent ──
        state.messages.append(("user", state.inputText))
        state.inputText = ""
        scenario("3. Message committed", delay: 0.5)

        // ── 4. Streaming ──
        animateStreaming([
            "Here's",
            "Here's a simple",
            "Here's a simple Fibonacci",
            "Here's a simple Fibonacci in Swift:"
        ], delay: 0.15)
        scenario("4. Assistant streaming", delay: 0.5)

        // ── 5. Tool call ──
        state.messages.append(("assistant", state.liveResponse))
        state.liveResponse = ""
        state.pendingTool = "read_file"
        scenario("5. Tool running", delay: 0.8)

        // ── 6. Tool done ──
        state.pendingTool = nil
        state.toolResult = "✅ read_file done"
        scenario("6. Tool completed", delay: 0.5)

        // ── 7. Second user message ──
        state.messages.append(("user", "now make it fail"))
        state.toolResult = nil
        scenario("7. Second user message", delay: 0.5)

        // ── 8. Error tool ──
        state.liveResponse = "I'll try to read a missing file..."
        scenario("8. Assistant starts error scenario", delay: 0.5)
        state.messages.append(("assistant", state.liveResponse))
        state.liveResponse = ""
        state.pendingTool = "read_file"
        scenario("9. Error tool running", delay: 0.8)
        state.pendingTool = nil
        state.isError = true
        state.toolResult = "❌ read_file failed: File not found"
        scenario("10. Error tool failed", delay: 0.5)

        // ── 11. Budget clipping ──
        state.isError = false
        state.toolResult = nil
        state.messages.append(("user", "explain recursion"))
        state.messages.append(("assistant", "Recursion is when a function calls itself."))
        state.messages.append(("user", "show example"))
        state.messages.append(("assistant", "func fib(_ n: Int) -> Int { return n <= 1 ? n : fib(n-1) + fib(n-2) }"))
        state.messages.append(("user", "optimize it"))
        state.inputText = "with memoization"
        scenario("11. Long history (budget clips head)", delay: 0.5)

        print("""
        
        ╔══════════════════════════════════════════════════════════╗
        ║  Demo complete.                                          ║
        ║                                                          ║
        ║  • Component protocol + AnyComponent for type erasure   ║
        ║  • VStack + @ComponentBuilder DSL                       ║
        ║  • FrameComposer assembles committed/live regions       ║
        ║  • LayoutBudget clips head, keeps tail, optional marker ║
        ║  • TUI.render(frame:) drives retained-mode output       ║
        ╚══════════════════════════════════════════════════════════╝
        """)
    }

    // MARK: - Animation

    private func animateTyping(_ text: String, delay: TimeInterval) {
        state.inputText = ""
        for char in text {
            state.inputText.append(char)
            let tty = VirtualTerminal(width: width, height: height)
            renderFrame(tty: tty)
            printFrame(tty: tty, label: "2. User typing")
            Thread.sleep(forTimeInterval: delay)
            moveCursorUp(lines: height + 3)
        }
    }

    private func animateStreaming(_ fragments: [String], delay: TimeInterval) {
        for fragment in fragments {
            state.liveResponse = fragment
            let tty = VirtualTerminal(width: width, height: height)
            renderFrame(tty: tty)
            printFrame(tty: tty, label: "4. Assistant streaming")
            Thread.sleep(forTimeInterval: delay)
            moveCursorUp(lines: height + 3)
        }
    }

    private func scenario(_ label: String, delay: TimeInterval) {
        let tty = VirtualTerminal(width: width, height: height)
        renderFrame(tty: tty)
        printFrame(tty: tty, label: label)
        Thread.sleep(forTimeInterval: delay)
    }

    // MARK: - Render

    private func renderFrame(tty: VirtualTerminal) {
        let tui = TUI(strategy: .legacyAbsolute, isTTY: true, terminal: tty)

        var committed: [AnyComponent] = []
        for (role, content) in state.messages {
            let prompt = role == "user" ? "❯ " : "  "
            committed.append(AnyComponent(TextInputComponent(prompt: prompt, value: content)))
        }
        if let result = state.toolResult {
            committed.append(AnyComponent(TextInputComponent(prompt: "  ", value: result)))
        }

        var live: [AnyComponent] = []
        if let tool = state.pendingTool {
            live.append(AnyComponent(TextInputComponent(prompt: "  ", value: "🔧 \(tool) running...")))
        }
        if !state.liveResponse.isEmpty {
            live.append(AnyComponent(TextInputComponent(prompt: "  ", value: state.liveResponse)))
        }
        live.append(AnyComponent(TextInputComponent(prompt: "❯ ", value: state.inputText)))

        let composer = FrameComposer(
            committed: committed,
            live: live,
            layoutBudget: LayoutBudget(maxRows: height, overflowMarker: "…")
        )

        let frame = composer.render(width: width)
        tui.render(frame: frame)
    }

    // MARK: - Output

    private func printFrame(tty: VirtualTerminal, label: String) {
        let header = "┌─ \(label) "
        let pad = width + 3 - header.count
        print(header + String(repeating: "─", count: max(0, pad)) + "┐")
        for line in tty.screenLines {
            print("│ \(line) │")
        }
        print("└" + String(repeating: "─", count: width + 2) + "┘")
    }

    private func moveCursorUp(lines: Int) {
        print("\u{1B}[\(lines)A", terminator: "")
        fflush(stdout)
    }
}

let demo = Demo()
demo.run()

// MARK: - Static Component Previews

print("\n" + String(repeating: "═", count: 66))
print("  COMPONENT PREVIEWS — modify Preview.swift to add your own")
print(String(repeating: "═", count: 66))

preview(TextInputComponent(prompt: "❯ ", value: "hello world"), label: "TextInput")

preview(ListPickerComponent(
    items: ["Option A", "Option B", "Option C"],
    selectedIndex: 1
), label: "ListPicker")

preview(VStack(spacing: 1) {
    TextInputComponent(prompt: "User: ", value: "explain recursion")
    TextInputComponent(prompt: "Bot:  ", value: "Recursion is when a function calls itself.")
    ListPickerComponent(items: ["Yes", "No"], selectedIndex: 0)
}, label: "VStack Mixed")

previewFrame(FrameComposer(
    committed: [
        AnyComponent(TextInputComponent(prompt: "❯ ", value: "msg 1")),
        AnyComponent(TextInputComponent(prompt: "  ", value: "reply 1"))
    ],
    live: [
        AnyComponent(TextInputComponent(prompt: "❯ ", value: "typing...")),
        AnyComponent(TextInputComponent(prompt: "  ", value: "🔧 tool running"))
    ],
    layoutBudget: LayoutBudget(maxRows: 6, overflowMarker: "…")
).render(width: 40), width: 40, height: 6, label: "FrameComposer")

preview(VStack {
    TextInputComponent(prompt: "❯ ", value: "old message")
    TextInputComponent(prompt: "❯ ", value: "another old")
    TextInputComponent(prompt: "❯ ", value: "latest")
}, width: 30, height: 4, label: "Budget Clip (head)")

// Color previews
runColorPreviews()
