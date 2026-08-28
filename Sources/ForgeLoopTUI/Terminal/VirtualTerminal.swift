import Foundation

/// In-memory virtual terminal: implements the `Terminal` protocol, for tests
/// and scenarios without a real TTY.
///
/// Currently a minimal terminal capable of interpreting TUI ANSI output, supporting:
/// - Plain character writes with automatic line wrapping
/// - `\r`, `\n`
/// - `ESC[2J` (clear screen), `ESC[H` (cursor home)
/// - `ESC[nA` (move up), `ESC[nB` (move down), `ESC[nC` (move right), `ESC[nD` (move left)
/// - `ESC[nG` (absolute cursor column, CHA)
/// - `ESC[2K` (clear current line)
///
/// Grid/cursor/scroll behavior will be further refined in later iterations.
/// Virtual terminal cell: a character and its current SGR style.
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

    /// A compact text representation of the current screen contents (trailing spaces and empty lines removed).
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

    /// Raw screen lines (spaces included, each fixed to `width` in length).
    public var screenLines: [String] {
        lock.withLock {
            grid.map { row in String(row.map(\.character)) }
        }
    }

    /// Raw screen cells (including style information).
    public var screenCells: [[Cell]] {
        lock.withLock {
            grid
        }
    }

    /// Resizes the virtual terminal.
    ///
    /// Semantics: preserves the top-left visible region, clips out-of-bounds content,
    /// fills newly added area with spaces, and clamps the cursor into the new bounds.
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

    /// Clears the screen and homes the cursor.
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
        case "G":
            let col = params.first ?? 1
            cursorCol = max(0, min(width - 1, col - 1))
        case "K":
            if params.first == 2 {
                clearCurrentLine()
            }
        case "L":
            insertLines(params.first ?? 1)
        case "M":
            deleteLines(params.first ?? 1)
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

    /// ESC[<n>L — 在当前光标行插入 n 行空白行。
    /// 光标行及以下内容下移，超出底部的行丢失。n 默认为 1，超界时 clamp 到剩余高度。
    private func insertLines(_ n: Int) {
        let count = max(1, min(n, height - cursorRow))
        guard count > 0 else { return }
        let blankCell = Cell(character: " ", style: SGRState())
        let blankRow = Array(repeating: blankCell, count: width)
        let keepAbove = Array(grid.prefix(cursorRow))
        let survivingShifted = Array(grid[cursorRow..<(height - count)])
        grid = keepAbove + Array(repeating: blankRow, count: count) + survivingShifted
    }

    /// ESC[<n>M — 删除当前光标行开始的 n 行。
    /// 下方内容上移，底部以空白行填充。n 默认为 1，超界时 clamp 到剩余高度。
    private func deleteLines(_ n: Int) {
        let count = max(1, min(n, height - cursorRow))
        guard count > 0 else { return }
        let blankCell = Cell(character: " ", style: SGRState())
        let blankRow = Array(repeating: blankCell, count: width)
        let keepAbove = Array(grid.prefix(cursorRow))
        let shiftUp = Array(grid.dropFirst(cursorRow + count))
        let padding = Array(repeating: blankRow, count: count)
        grid = keepAbove + shiftUp + padding
    }
}
