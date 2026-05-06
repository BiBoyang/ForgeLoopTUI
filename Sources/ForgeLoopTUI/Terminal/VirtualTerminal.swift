import Foundation

/// 内存中的虚拟终端：实现 `Terminal` 协议，用于测试与无真实 TTY 场景。
///
/// 当前为可解释 TUI ANSI 输出的最小终端，支持：
/// - 普通字符写入与自动换行
/// - `\r`、`\n`
/// - `ESC[2J`（清屏）、`ESC[H`（归位）
/// - `ESC[nA`（上移）、`ESC[nB`（下移）、`ESC[nC`（右移）、`ESC[nD`（左移）
/// - `ESC[2K`（清除当前行）
///
/// 网格/光标/滚屏行为将在后续迭代继续深化。
/// 虚拟终端单元格：字符及其当前 SGR 样式。
public struct Cell: Sendable, Equatable {
    public var character: Character
    public var style: SGRState
}

public final class VirtualTerminal: Terminal, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var width: Int
    public private(set) var height: Int
    public private(set) var cursorRow: Int
    public private(set) var cursorCol: Int
    private var grid: [[Cell]]
    private var currentStyle = SGRState()
    private var parser = ANSIParser()

    public var isTTY: Bool { false }
    public var capability: TerminalCapability { .truecolor }

    public init(width: Int = 80, height: Int = 24) {
        let safeWidth = max(1, width)
        let safeHeight = max(1, height)
        self.width = safeWidth
        self.height = safeHeight
        self.cursorRow = 0
        self.cursorCol = 0
        let blankCell = Cell(character: " ", style: SGRState())
        self.grid = (0..<safeHeight).map { _ in Array(repeating: blankCell, count: safeWidth) }
    }

    public func write(_ text: String) {
        lock.withLock {
            for scalar in text.unicodeScalars {
                parser.feed(scalar) { [self] event in
                    switch event {
                    case .text(let char):
                        if char == "\r" {
                            cursorCol = 0
                        } else if char == "\n" {
                            moveCursorDown()
                        } else {
                            writeCharacter(char)
                        }
                    case .csi(let params, _, let command):
                        handleCSI(params: params, command: command)
                    }
                }
            }
        }
    }

    /// 当前屏幕内容的紧凑文本表示（去除尾部空格与空行）。
    public var buffer: String {
        lock.withLock {
            var lines = grid.map { row in String(row.map(\.character)) }
            for i in lines.indices {
                while lines[i].hasSuffix(" ") {
                    lines[i].removeLast()
                }
            }
            while lines.last?.isEmpty == true {
                lines.removeLast()
            }
            return lines.joined(separator: "\n")
        }
    }

    /// 原始屏幕行（包含空格，长度固定为 `width`）。
    public var screenLines: [String] {
        lock.withLock {
            grid.map { row in String(row.map(\.character)) }
        }
    }

    /// 原始屏幕单元格（包含样式信息）。
    public var screenCells: [[Cell]] {
        lock.withLock {
            grid
        }
    }

    /// 调整虚拟终端尺寸。
    ///
    /// 语义：保留左上可见区域，裁剪越界内容，新增区域以空格填充，光标收敛到新边界内。
    public func resize(width newWidth: Int, height newHeight: Int) {
        lock.withLock {
            let oldWidth = width
            let oldHeight = height
            let safeWidth = max(1, newWidth)
            let safeHeight = max(1, newHeight)

            let blankCell = Cell(character: " ", style: SGRState())
            var newGrid: [[Cell]] = []
            for row in 0..<safeHeight {
                if row < oldHeight {
                    let oldRow = grid[row]
                    let preserved = Array(oldRow.prefix(min(oldWidth, safeWidth)))
                    let padding = Array(repeating: blankCell, count: max(0, safeWidth - oldWidth))
                    newGrid.append(preserved + padding)
                } else {
                    newGrid.append(Array(repeating: blankCell, count: safeWidth))
                }
            }

            grid = newGrid
            width = safeWidth
            height = safeHeight
            cursorRow = min(cursorRow, safeHeight - 1)
            cursorCol = min(cursorCol, safeWidth - 1)
        }
    }

    /// 清空屏幕并将光标归位。
    public func clear() {
        lock.withLock {
            clearScreen()
        }
    }

    // MARK: - Private

    private func writeCharacter(_ char: Character) {
        guard cursorRow >= 0 && cursorRow < height && cursorCol >= 0 && cursorCol < width else { return }
        grid[cursorRow][cursorCol] = Cell(character: char, style: currentStyle)
        cursorCol += 1
        if cursorCol >= width {
            cursorCol = 0
            cursorRow += 1
            if cursorRow >= height {
                scrollUp()
                cursorRow = height - 1
            }
        }
    }

    private func moveCursorDown() {
        cursorRow += 1
        if cursorRow >= height {
            scrollUp()
            cursorRow = height - 1
        }
    }

    private func handleCSI(params: [Int], command: Character) {
        switch command {
        case "J":
            if params.first == 2 {
                clearScreen()
            }
        case "H":
            let row = params.count > 0 ? params[0] : 1
            let col = params.count > 1 ? params[1] : 1
            cursorRow = max(0, min(height - 1, row - 1))
            cursorCol = max(0, min(width - 1, col - 1))
        case "A":
            cursorRow = max(0, cursorRow - (params.first ?? 1))
        case "B":
            cursorRow = min(height - 1, cursorRow + (params.first ?? 1))
        case "C":
            cursorCol = min(width - 1, cursorCol + (params.first ?? 1))
        case "D":
            cursorCol = max(0, cursorCol - (params.first ?? 1))
        case "K":
            if params.first == 2 {
                clearCurrentLine()
            }
        case "m":
            currentStyle.apply(params)
        default:
            break // 忽略未支持的序列
        }
    }

    private func clearScreen() {
        let blankCell = Cell(character: " ", style: SGRState())
        grid = (0..<height).map { _ in Array(repeating: blankCell, count: width) }
        cursorRow = 0
        cursorCol = 0
        currentStyle.reset()
    }

    private func clearCurrentLine() {
        guard cursorRow >= 0 && cursorRow < height else { return }
        let blankCell = Cell(character: " ", style: SGRState())
        for c in 0..<width {
            grid[cursorRow][c] = blankCell
        }
    }

    private func scrollUp() {
        let blankCell = Cell(character: " ", style: SGRState())
        grid.removeFirst()
        grid.append(Array(repeating: blankCell, count: width))
    }
}
