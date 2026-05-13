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
/// Width is counted by **visible cells** via ``visibleWidth(_:)``: ASCII
/// glyphs take 1 cell, full-width CJK glyphs take 2 cells, control glyphs
/// take 0 cells. The internal cursor index (``MultiLineInputState/cursorColumn``)
/// is still a character index — the viewport only changes how `moveUp` /
/// `moveDown` map between *visible columns* and character indices, so
/// `Viewport` is purely additive and does not affect any other action.
///
/// 稳定等级: Stable。
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
    private var preferredVisualColumn: Int
    private var preferredVisualColumnNeedsRefresh: Bool

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
        self.preferredVisualColumn = Self.visibleColumn(in: split[self.cursorRow], charIndex: self.cursorColumn)
        self.preferredVisualColumnNeedsRefresh = false
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
            syncPreferredColumnsToCursor()
        case .moveToLineEnd:
            cursorColumn = lines[cursorRow].count
            syncPreferredColumnsToCursor()
        case .moveToBufferStart:
            cursorRow = 0
            cursorColumn = 0
            syncPreferredColumnsToCursor()
        case .moveToBufferEnd:
            cursorRow = lines.count - 1
            cursorColumn = lines[cursorRow].count
            syncPreferredColumnsToCursor()
        case .killToLineStart:
            killToLineStart()
        case .killToLineEnd:
            killToLineEnd()
        case .replace(let string):
            let split = Self.splitLines(string)
            lines = split
            cursorRow = split.count - 1
            cursorColumn = split[split.count - 1].count
            syncPreferredColumnsToCursor()
        case .clear:
            lines = [""]
            cursorRow = 0
            cursorColumn = 0
            syncPreferredColumnsToCursor()
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
        syncPreferredColumnsToCursor()
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
        syncPreferredColumnsToCursor()
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
        syncPreferredColumnsToCursor()
    }

    private mutating func backspace() {
        if cursorColumn > 0 {
            var line = lines[cursorRow]
            let start = line.index(line.startIndex, offsetBy: cursorColumn - 1)
            let end = line.index(after: start)
            line.removeSubrange(start..<end)
            lines[cursorRow] = line
            cursorColumn -= 1
            syncPreferredColumnsToCursor()
        } else if cursorRow > 0 {
            let prev = lines[cursorRow - 1]
            let current = lines[cursorRow]
            let newColumn = prev.count
            lines[cursorRow - 1] = prev + current
            lines.remove(at: cursorRow)
            cursorRow -= 1
            cursorColumn = newColumn
            syncPreferredColumnsToCursor()
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
        syncPreferredColumnsToCursor()
    }

    private mutating func moveRight() {
        let lineLen = lines[cursorRow].count
        if cursorColumn < lineLen {
            cursorColumn += 1
        } else if cursorRow < lines.count - 1 {
            cursorRow += 1
            cursorColumn = 0
        }
        syncPreferredColumnsToCursor()
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
        let currentLine = lines[cursorRow]
        let currentVisualColumn = Self.visibleColumn(in: currentLine, charIndex: cursorColumn)
        let visualRowInRow = currentVisualColumn / width
        let preferredVisualCol = currentPreferredVisualColumn() % width

        if visualRowInRow > 0 {
            // Stay on the same logical line, jump up one visual row.
            let targetVisualRowInRow = visualRowInRow - 1
            let targetVisibleColumn = targetVisualRowInRow * width + preferredVisualCol
            cursorColumn = Self.charIndex(in: currentLine, atVisibleColumn: targetVisibleColumn)
            return
        }
        // We're on the top visual row of this logical line; cross to previous line.
        guard cursorRow > 0 else { return }
        cursorRow -= 1
        let previousLine = lines[cursorRow]
        let prevVisualRows = visualRowCount(forLine: previousLine, width: width)
        let targetVisualRowInRow = prevVisualRows - 1
        let targetVisibleColumn = targetVisualRowInRow * width + preferredVisualCol
        cursorColumn = Self.charIndex(in: previousLine, atVisibleColumn: targetVisibleColumn)
    }

    private mutating func moveDownVisual(width: Int) {
        let currentLine = lines[cursorRow]
        let currentVisualColumn = Self.visibleColumn(in: currentLine, charIndex: cursorColumn)
        let visualRowInRow = currentVisualColumn / width
        let preferredVisualCol = currentPreferredVisualColumn() % width
        let totalVisualRows = visualRowCount(forLine: currentLine, width: width)

        if visualRowInRow + 1 < totalVisualRows {
            // Stay on the same logical line, drop down one visual row.
            let targetVisualRowInRow = visualRowInRow + 1
            let targetVisibleColumn = targetVisualRowInRow * width + preferredVisualCol
            cursorColumn = Self.charIndex(in: currentLine, atVisibleColumn: targetVisibleColumn)
            return
        }
        // We're on the bottom visual row of this logical line; cross to next line.
        guard cursorRow < lines.count - 1 else { return }
        cursorRow += 1
        let nextLine = lines[cursorRow]
        cursorColumn = Self.charIndex(in: nextLine, atVisibleColumn: preferredVisualCol)
    }

    private func visualRowCount(forLine line: String, width: Int) -> Int {
        let totalWidth = visibleWidth(line)
        if totalWidth == 0 { return 1 }
        return (totalWidth + width - 1) / width
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
        syncPreferredColumnsToCursor()
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

    private mutating func syncPreferredColumnsToCursor() {
        preferredColumn = cursorColumn
        preferredVisualColumnNeedsRefresh = true
    }

    private mutating func currentPreferredVisualColumn() -> Int {
        if preferredVisualColumnNeedsRefresh {
            preferredVisualColumn = Self.visibleColumn(in: lines[cursorRow], charIndex: preferredColumn)
            preferredVisualColumnNeedsRefresh = false
        }
        return preferredVisualColumn
    }

    private static func visibleColumn(in line: String, charIndex: Int) -> Int {
        let clamped = min(max(0, charIndex), line.count)
        guard clamped > 0 else { return 0 }
        let split = line.index(line.startIndex, offsetBy: clamped)
        return visibleWidth(String(line[line.startIndex..<split]))
    }

    private static func charIndex(in line: String, atVisibleColumn col: Int) -> Int {
        let target = max(0, col)
        guard target > 0 else { return 0 }

        var consumedVisibleColumns = 0
        var index = 0
        for character in line {
            let width = characterVisibleWidth(character)
            if width == 0 {
                index += 1
                continue
            }
            if target < consumedVisibleColumns + width {
                return index
            }
            consumedVisibleColumns += width
            index += 1
        }
        return line.count
    }

    /// Inline width lookup for a single `Character` — avoids the `String`
    /// allocation and `ansiStripped` overhead of `visibleWidth(String(character))`.
    private static func characterVisibleWidth(_ character: Character) -> Int {
        let scalars = character.unicodeScalars

        // Fast path: single scalar (covers ASCII, CJK, emoji, and most glyphs).
        if scalars.count == 1, let scalar = scalars.first {
            let value = scalar.value
            if value < 0x20 || value == 0x7F {
                return 0
            }
            if value < 0x7F {
                return 1
            }
            return scalarIsWide(value) ? 2 : 1
        }

        // Fallback: multi-scalar grapheme clusters (e.g. emoji with ZWJ or
        // skin-tone modifiers).  Sums per-scalar widths to stay identical to
        // `visibleWidth(_:)`.
        var width = 0
        for scalar in scalars {
            let value = scalar.value
            if value < 0x20 || value == 0x7F {
                continue
            }
            if value < 0x7F {
                width += 1
                continue
            }
            width += scalarIsWide(value) ? 2 : 1
        }
        return width
    }

    private static func scalarIsWide(_ value: UInt32) -> Bool {
        (0x1100...0x115F).contains(value)
            || (0x231A...0x231B).contains(value)
            || (0x2329...0x232A).contains(value)
            || (0x23E9...0x23EC).contains(value)
            || (0x23F0...0x23F0).contains(value)
            || (0x23F3...0x23F3).contains(value)
            || (0x25FD...0x25FE).contains(value)
            || (0x2614...0x2615).contains(value)
            || (0x2648...0x2653).contains(value)
            || (0x267F...0x267F).contains(value)
            || (0x2693...0x2693).contains(value)
            || (0x26A1...0x26A1).contains(value)
            || (0x26AA...0x26AB).contains(value)
            || (0x26BD...0x26BE).contains(value)
            || (0x26C4...0x26C5).contains(value)
            || (0x26CE...0x26CE).contains(value)
            || (0x26D4...0x26D4).contains(value)
            || (0x26EA...0x26EA).contains(value)
            || (0x26F2...0x26F3).contains(value)
            || (0x26F5...0x26F5).contains(value)
            || (0x26FA...0x26FA).contains(value)
            || (0x26FD...0x26FD).contains(value)
            || (0x2705...0x2705).contains(value)
            || (0x270A...0x270B).contains(value)
            || (0x2728...0x2728).contains(value)
            || (0x274C...0x274C).contains(value)
            || (0x274E...0x274E).contains(value)
            || (0x2753...0x2755).contains(value)
            || (0x2795...0x2797).contains(value)
            || (0x27B0...0x27B0).contains(value)
            || (0x27BF...0x27BF).contains(value)
            || (0x2B1B...0x2B1C).contains(value)
            || (0x2B50...0x2B50).contains(value)
            || (0x2B55...0x2B55).contains(value)
            || (0x2E80...0x303E).contains(value)
            || (0x3041...0x3096).contains(value)
            || (0x3099...0x30FF).contains(value)
            || (0x3105...0x312F).contains(value)
            || (0x3131...0x318E).contains(value)
            || (0x3190...0x31BA).contains(value)
            || (0x31C0...0x31E3).contains(value)
            || (0x31F0...0x321E).contains(value)
            || (0x3220...0x3247).contains(value)
            || (0x3250...0x32FE).contains(value)
            || (0x3300...0x4DBF).contains(value)
            || (0x4E00...0xA48C).contains(value)
            || (0xA490...0xA4C6).contains(value)
            || (0xA960...0xA97C).contains(value)
            || (0xAC00...0xD7A3).contains(value)
            || (0xF900...0xFAFF).contains(value)
            || (0xFE10...0xFE19).contains(value)
            || (0xFE30...0xFE52).contains(value)
            || (0xFE54...0xFE66).contains(value)
            || (0xFE68...0xFE6B).contains(value)
            || (0xFF01...0xFF60).contains(value)
            || (0xFFE0...0xFFE6).contains(value)
            || (0x1F100...0x1F10A).contains(value)
            || (0x1F110...0x1F12D).contains(value)
            || (0x1F130...0x1F169).contains(value)
            || (0x1F170...0x1F19A).contains(value)
            || (0x1F200...0x1F202).contains(value)
            || (0x1F210...0x1F23B).contains(value)
            || (0x1F240...0x1F248).contains(value)
            || (0x1F250...0x1F251).contains(value)
            || (0x1F260...0x1F265).contains(value)
            || (0x1F300...0x1F320).contains(value)
            || (0x1F32D...0x1F335).contains(value)
            || (0x1F337...0x1F37C).contains(value)
            || (0x1F37E...0x1F393).contains(value)
            || (0x1F3A0...0x1F3CA).contains(value)
            || (0x1F3CF...0x1F3D3).contains(value)
            || (0x1F3E0...0x1F3F0).contains(value)
            || (0x1F3F4...0x1F3F4).contains(value)
            || (0x1F3F8...0x1F43E).contains(value)
            || (0x1F440...0x1F440).contains(value)
            || (0x1F442...0x1F4FC).contains(value)
            || (0x1F4FF...0x1F53D).contains(value)
            || (0x1F54B...0x1F54E).contains(value)
            || (0x1F550...0x1F567).contains(value)
            || (0x1F57A...0x1F57A).contains(value)
            || (0x1F595...0x1F596).contains(value)
            || (0x1F5A4...0x1F5A4).contains(value)
            || (0x1F5FB...0x1F64F).contains(value)
            || (0x1F680...0x1F6C5).contains(value)
            || (0x1F6CC...0x1F6CC).contains(value)
            || (0x1F6D0...0x1F6D2).contains(value)
            || (0x1F6EB...0x1F6EC).contains(value)
            || (0x1F6F4...0x1F6F9).contains(value)
            || (0x1F910...0x1F93E).contains(value)
            || (0x1F940...0x1F970).contains(value)
            || (0x1F973...0x1F976).contains(value)
            || (0x1F97A...0x1F97A).contains(value)
            || (0x1F97C...0x1F9A2).contains(value)
            || (0x1F9B0...0x1F9B9).contains(value)
            || (0x1F9C0...0x1F9C2).contains(value)
            || (0x1F9D0...0x1F9FF).contains(value)
            || (0x20000...0x2FFFD).contains(value)
            || (0x30000...0x3FFFD).contains(value)
    }
}
