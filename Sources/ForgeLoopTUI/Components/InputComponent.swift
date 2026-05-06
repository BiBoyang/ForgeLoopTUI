import Foundation

public enum TextInputAction: Sendable, Equatable {
    case insert(Character)
    case insertText(String)
    case backspace
    case deleteForward
    case moveLeft
    case moveRight
    case moveToStart
    case moveToEnd
    case replace(String)
    case clear
}

public struct TextInputRenderResult: Sendable, Equatable {
    public let line: String
    public let cursorOffset: Int
    public let visibleText: String
    public let scrollOffset: Int

    public init(line: String, cursorOffset: Int, visibleText: String, scrollOffset: Int) {
        self.line = line
        self.cursorOffset = cursorOffset
        self.visibleText = visibleText
        self.scrollOffset = scrollOffset
    }
}

public struct TextInputState: Sendable, Equatable {
    public private(set) var text: String
    public private(set) var cursorPosition: Int
    public private(set) var scrollOffset: Int

    public init(text: String = "", cursorAtEnd: Bool = true, scrollOffset: Int = 0) {
        let normalized = Self.normalize(text)
        self.text = normalized
        let count = normalized.count
        self.cursorPosition = cursorAtEnd ? count : 0
        self.scrollOffset = max(0, scrollOffset)
    }

    public var isEmpty: Bool {
        text.isEmpty
    }

    public mutating func handle(_ action: TextInputAction) {
        switch action {
        case .insert(let character):
            insert(Self.normalize(String(character)))
        case .insertText(let string):
            insert(Self.normalize(string))
        case .backspace:
            guard cursorPosition > 0 else { return }
            let start = text.index(text.startIndex, offsetBy: cursorPosition - 1)
            let end = text.index(after: start)
            text.removeSubrange(start..<end)
            cursorPosition -= 1
        case .deleteForward:
            guard cursorPosition < text.count else { return }
            let start = text.index(text.startIndex, offsetBy: cursorPosition)
            let end = text.index(after: start)
            text.removeSubrange(start..<end)
        case .moveLeft:
            cursorPosition = max(0, cursorPosition - 1)
        case .moveRight:
            cursorPosition = min(text.count, cursorPosition + 1)
        case .moveToStart:
            cursorPosition = 0
        case .moveToEnd:
            cursorPosition = text.count
        case .replace(let string):
            text = Self.normalize(string)
            cursorPosition = text.count
            scrollOffset = 0
        case .clear:
            text = ""
            cursorPosition = 0
            scrollOffset = 0
        }
    }

    public mutating func render(prefix: String = "", totalWidth: Int) -> TextInputRenderResult {
        let prefixWidth = visibleWidth(prefix)
        let viewportWidth = max(1, totalWidth - prefixWidth)
        let characters = Array(text)
        let boundaries = Self.columnBoundaries(for: characters)
        let fullTextWidth = boundaries.last ?? 0
        let cursorColumn = boundaries[min(cursorPosition, characters.count)]

        let maxScrollTarget = max(0, fullTextWidth - viewportWidth)
        scrollOffset = Self.snapBoundary(atMost: min(scrollOffset, maxScrollTarget), boundaries: boundaries)

        if cursorColumn < scrollOffset {
            scrollOffset = Self.snapBoundary(atMost: cursorColumn, boundaries: boundaries)
        } else if cursorColumn > scrollOffset + viewportWidth {
            scrollOffset = Self.snapBoundary(
                atMost: max(0, cursorColumn - viewportWidth),
                boundaries: boundaries
            )
        }

        let startIndex = boundaries.firstIndex(of: scrollOffset) ?? 0
        var endIndex = startIndex
        while endIndex < characters.count {
            let nextBoundary = boundaries[endIndex + 1]
            if nextBoundary - scrollOffset > viewportWidth {
                break
            }
            endIndex += 1
        }
        if startIndex < characters.count, endIndex == startIndex {
            endIndex += 1
        }

        let visibleText = String(characters[startIndex..<endIndex])
        let visibleTextWidth = visibleWidth(visibleText)
        let cursorColumnInViewport = min(visibleTextWidth, max(0, cursorColumn - scrollOffset))
        let cursorOffset = max(0, visibleTextWidth - cursorColumnInViewport)

        return TextInputRenderResult(
            line: prefix + visibleText,
            cursorOffset: cursorOffset,
            visibleText: visibleText,
            scrollOffset: scrollOffset
        )
    }

    private mutating func insert(_ string: String) {
        guard !string.isEmpty else { return }
        let insertionIndex = text.index(text.startIndex, offsetBy: cursorPosition)
        text.insert(contentsOf: string, at: insertionIndex)
        cursorPosition += string.count
    }

    private static func normalize(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func columnBoundaries(for characters: [Character]) -> [Int] {
        var boundaries: [Int] = [0]
        boundaries.reserveCapacity(characters.count + 1)
        for character in characters {
            let width = visibleWidth(String(character))
            boundaries.append((boundaries.last ?? 0) + max(1, width))
        }
        return boundaries
    }

    private static func snapBoundary(atMost target: Int, boundaries: [Int]) -> Int {
        var snapped = 0
        for boundary in boundaries {
            if boundary > target {
                break
            }
            snapped = boundary
        }
        return snapped
    }
}
