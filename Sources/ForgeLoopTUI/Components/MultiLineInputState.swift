import Foundation

public enum MultiLineInputAction: Sendable, Equatable {
    case insert(Character)
    case insertText(String)
    case insertNewline
    case backspace
    case deleteForward
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case moveToLineStart
    case moveToLineEnd
    case moveToBufferStart
    case moveToBufferEnd
    case killToLineStart
    case killToLineEnd
    case replace(String)
    case clear
}

public struct CursorPlacement: Sendable, Equatable {
    public let up: Int
    public let offset: Int

    public init(up: Int, offset: Int) {
        self.up = max(0, up)
        self.offset = max(0, offset)
    }
}

public struct MultiLineInputRenderResult: Sendable, Equatable {
    public let lines: [String]
    public let cursor: CursorPlacement

    public init(lines: [String], cursor: CursorPlacement) {
        self.lines = lines
        self.cursor = cursor
    }
}

/// Optional viewport hint for ``MultiLineInputState``.
///
/// When set, vertical cursor moves (``MultiLineInputAction/moveUp`` /
/// ``MultiLineInputAction/moveDown``) walk by *visual* rows that respect
/// soft-wrap at `width`, rather than by purely logical rows. This matches
/// what the user sees on screen for long single-line input or wide CJK
/// content while keeping the buffer model line-based.
///
/// Width is counted by character count (one cell per `Character`). Mixed-CJK
/// content using wide cells is supported by the higher-level renderer; the
/// cursor model itself is character-indexed.
///
/// 稳定等级: Provisional。
public struct Viewport: Sendable, Equatable {
    public let width: Int

    public init(width: Int) {
        precondition(width > 0, "Viewport.width must be a positive integer")
        self.width = width
    }
}

public struct MultiLineInputState: Sendable, Equatable {
    public private(set) var lines: [String]
    public private(set) var cursorRow: Int
    public private(set) var cursorColumn: Int
    public private(set) var viewport: Viewport?
    private var preferredColumn: Int

    public init(text: String = "", cursorAtEnd: Bool = true, viewport: Viewport? = nil) {
        let split = Self.splitLines(text)
        self.lines = split
        if cursorAtEnd {
            self.cursorRow = split.count - 1
            self.cursorColumn = split[split.count - 1].count
        } else {
            self.cursorRow = 0
            self.cursorColumn = 0
        }
        self.preferredColumn = self.cursorColumn
        self.viewport = viewport
    }

    public var text: String {
        lines.joined(separator: "\n")
    }

    public var isEmpty: Bool {
        lines.count == 1 && lines[0].isEmpty
    }

    public mutating func handle(_ action: MultiLineInputAction) {
        switch action {
        case .insert(let character):
            if character == "\n" || character == "\r" {
                insertNewline()
            } else if Self.shouldRejectInsertCharacter(character) {
                // 防御:避免控制字符破坏 lines 不变量(只有 \n 才是分行符)。
                return
            } else {
                insertString(String(character))
            }
        case .insertText(let string):
            insertText(string)
        case .insertNewline:
            insertNewline()
        case .backspace:
            backspace()
        case .deleteForward:
            deleteForward()
        case .moveLeft:
            moveLeft()
        case .moveRight:
            moveRight()
        case .moveUp:
            moveUp()
        case .moveDown:
            moveDown()
        case .moveToLineStart:
            cursorColumn = 0
            preferredColumn = 0
        case .moveToLineEnd:
            cursorColumn = lines[cursorRow].count
            preferredColumn = cursorColumn
        case .moveToBufferStart:
            cursorRow = 0
            cursorColumn = 0
            preferredColumn = 0
        case .moveToBufferEnd:
            cursorRow = lines.count - 1
            cursorColumn = lines[cursorRow].count
            preferredColumn = cursorColumn
        case .killToLineStart:
            killToLineStart()
        case .killToLineEnd:
            killToLineEnd()
        case .replace(let string):
            let split = Self.splitLines(string)
            lines = split
            cursorRow = split.count - 1
            cursorColumn = split[split.count - 1].count
            preferredColumn = cursorColumn
        case .clear:
            lines = [""]
            cursorRow = 0
            cursorColumn = 0
            preferredColumn = 0
        }
    }

    public func render() -> MultiLineInputRenderResult {
        let lastIndex = lines.count - 1
        let up = lastIndex - cursorRow
        let cursorLine = lines[cursorRow]
        let prefix = String(cursorLine.prefix(cursorColumn))
        let cursorVisibleColumn = visibleWidth(prefix)
        let targetRowVisibleWidth = visibleWidth(cursorLine)
        let offset = max(0, targetRowVisibleWidth - cursorVisibleColumn)
        return MultiLineInputRenderResult(
            lines: lines,
            cursor: CursorPlacement(up: up, offset: offset)
        )
    }

    private mutating func insertString(_ string: String) {
        guard !string.isEmpty else { return }
        var line = lines[cursorRow]
        let idx = line.index(line.startIndex, offsetBy: cursorColumn)
        line.insert(contentsOf: string, at: idx)
        lines[cursorRow] = line
        cursorColumn += string.count
        preferredColumn = cursorColumn
    }

    private mutating func insertText(_ string: String) {
        let normalized = string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let parts = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else { return }
        if parts.count == 1 {
            insertString(parts[0])
            return
        }
        let current = lines[cursorRow]
        let splitIdx = current.index(current.startIndex, offsetBy: cursorColumn)
        let head = String(current[current.startIndex..<splitIdx])
        let tail = String(current[splitIdx..<current.endIndex])

        var newLines: [String] = []
        newLines.reserveCapacity(parts.count)
        newLines.append(head + parts[0])
        if parts.count > 2 {
            for i in 1..<(parts.count - 1) {
                newLines.append(parts[i])
            }
        }
        newLines.append(parts[parts.count - 1] + tail)

        lines.replaceSubrange(cursorRow...cursorRow, with: newLines)
        cursorRow += parts.count - 1
        cursorColumn = parts[parts.count - 1].count
        preferredColumn = cursorColumn
    }

    private mutating func insertNewline() {
        let current = lines[cursorRow]
        let splitIdx = current.index(current.startIndex, offsetBy: cursorColumn)
        let head = String(current[current.startIndex..<splitIdx])
        let tail = String(current[splitIdx..<current.endIndex])
        lines[cursorRow] = head
        lines.insert(tail, at: cursorRow + 1)
        cursorRow += 1
        cursorColumn = 0
        preferredColumn = 0
    }

    private mutating func backspace() {
        if cursorColumn > 0 {
            var line = lines[cursorRow]
            let start = line.index(line.startIndex, offsetBy: cursorColumn - 1)
            let end = line.index(after: start)
            line.removeSubrange(start..<end)
            lines[cursorRow] = line
            cursorColumn -= 1
            preferredColumn = cursorColumn
        } else if cursorRow > 0 {
            let prev = lines[cursorRow - 1]
            let current = lines[cursorRow]
            let newColumn = prev.count
            lines[cursorRow - 1] = prev + current
            lines.remove(at: cursorRow)
            cursorRow -= 1
            cursorColumn = newColumn
            preferredColumn = cursorColumn
        }
    }

    private mutating func deleteForward() {
        let line = lines[cursorRow]
        if cursorColumn < line.count {
            var newLine = line
            let start = newLine.index(newLine.startIndex, offsetBy: cursorColumn)
            let end = newLine.index(after: start)
            newLine.removeSubrange(start..<end)
            lines[cursorRow] = newLine
        } else if cursorRow < lines.count - 1 {
            let next = lines[cursorRow + 1]
            lines[cursorRow] = line + next
            lines.remove(at: cursorRow + 1)
        }
    }

    private mutating func moveLeft() {
        if cursorColumn > 0 {
            cursorColumn -= 1
        } else if cursorRow > 0 {
            cursorRow -= 1
            cursorColumn = lines[cursorRow].count
        }
        preferredColumn = cursorColumn
    }

    private mutating func moveRight() {
        let lineLen = lines[cursorRow].count
        if cursorColumn < lineLen {
            cursorColumn += 1
        } else if cursorRow < lines.count - 1 {
            cursorRow += 1
            cursorColumn = 0
        }
        preferredColumn = cursorColumn
    }

    private mutating func moveUp() {
        if let viewport {
            moveUpVisual(width: viewport.width)
        } else {
            moveUpLogical()
        }
    }

    private mutating func moveDown() {
        if let viewport {
            moveDownVisual(width: viewport.width)
        } else {
            moveDownLogical()
        }
    }

    private mutating func moveUpLogical() {
        guard cursorRow > 0 else { return }
        cursorRow -= 1
        cursorColumn = min(preferredColumn, lines[cursorRow].count)
    }

    private mutating func moveDownLogical() {
        guard cursorRow < lines.count - 1 else { return }
        cursorRow += 1
        cursorColumn = min(preferredColumn, lines[cursorRow].count)
    }

    private mutating func moveUpVisual(width: Int) {
        // Visual row counts: each logical line takes
        // max(1, ceil(charCount / width)) visual rows.
        let visualRowInRow = cursorColumn / width
        let preferredVisualCol = preferredColumn % width

        if visualRowInRow > 0 {
            // Stay on the same logical line, jump up one visual row.
            let targetVisualRowInRow = visualRowInRow - 1
            let lineLen = lines[cursorRow].count
            let candidate = targetVisualRowInRow * width + preferredVisualCol
            cursorColumn = min(candidate, lineLen)
            return
        }
        // We're on the top visual row of this logical line; cross to previous line.
        guard cursorRow > 0 else { return }
        cursorRow -= 1
        let prevLen = lines[cursorRow].count
        let prevVisualRows = visualRowCount(forLineOfLength: prevLen, width: width)
        let targetVisualRowInRow = prevVisualRows - 1
        let candidate = targetVisualRowInRow * width + preferredVisualCol
        cursorColumn = min(candidate, prevLen)
    }

    private mutating func moveDownVisual(width: Int) {
        let visualRowInRow = cursorColumn / width
        let preferredVisualCol = preferredColumn % width
        let lineLen = lines[cursorRow].count
        let totalVisualRows = visualRowCount(forLineOfLength: lineLen, width: width)

        if visualRowInRow + 1 < totalVisualRows {
            // Stay on the same logical line, drop down one visual row.
            let targetVisualRowInRow = visualRowInRow + 1
            let candidate = targetVisualRowInRow * width + preferredVisualCol
            cursorColumn = min(candidate, lineLen)
            return
        }
        // We're on the bottom visual row of this logical line; cross to next line.
        guard cursorRow < lines.count - 1 else { return }
        cursorRow += 1
        let nextLen = lines[cursorRow].count
        let candidate = preferredVisualCol
        cursorColumn = min(candidate, nextLen)
    }

    private func visualRowCount(forLineOfLength len: Int, width: Int) -> Int {
        if len == 0 { return 1 }
        return (len + width - 1) / width
    }

    /// Update the viewport hint. Pass `nil` to disable visual-row navigation
    /// and revert to logical-row moves.
    public mutating func setViewport(_ viewport: Viewport?) {
        self.viewport = viewport
    }

    private mutating func killToLineStart() {
        var line = lines[cursorRow]
        let end = line.index(line.startIndex, offsetBy: cursorColumn)
        line.removeSubrange(line.startIndex..<end)
        lines[cursorRow] = line
        cursorColumn = 0
        preferredColumn = 0
    }

    private mutating func killToLineEnd() {
        var line = lines[cursorRow]
        let start = line.index(line.startIndex, offsetBy: cursorColumn)
        line.removeSubrange(start..<line.endIndex)
        lines[cursorRow] = line
    }

    private static func splitLines(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalized.isEmpty {
            return [""]
        }
        return normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private static func shouldRejectInsertCharacter(_ ch: Character) -> Bool {
        guard ch.unicodeScalars.count == 1, let scalar = ch.unicodeScalars.first else {
            return false
        }
        let value = scalar.value
        // Tab 视为可见输入,放行;其他 C0 控制字符与 DEL 拒绝。
        if value == 0x09 { return false }
        if value < 0x20 { return true }
        if value == 0x7F { return true }
        return false
    }
}
