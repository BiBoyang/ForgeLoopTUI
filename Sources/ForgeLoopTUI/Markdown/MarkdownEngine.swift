import Foundation

public protocol MarkdownEngine: AnyObject {
    func reset()
    func render(text: String, isFinal: Bool) -> [String]
}

public struct MarkdownRenderOptions: Sendable, Equatable {
    public var tablePolicy: TableRenderPolicy

    public init(tablePolicy: TableRenderPolicy = .default) {
        self.tablePolicy = tablePolicy
    }
}

public struct TableRenderPolicy: Sendable, Equatable {
    public var maxRenderedWidth: Int
    public var minColumnWidth: Int
    public var maxColumnWidth: Int?
    public var truncationIndicator: String
    public var overflowBehavior: TableOverflowBehavior

    public static let `default` = TableRenderPolicy(
        maxRenderedWidth: 80,
        minColumnWidth: 6,
        maxColumnWidth: 24,
        truncationIndicator: "…",
        overflowBehavior: .compactThenTruncateThenDegrade
    )

    public init(
        maxRenderedWidth: Int = 80,
        minColumnWidth: Int = 6,
        maxColumnWidth: Int? = 24,
        truncationIndicator: String = "…",
        overflowBehavior: TableOverflowBehavior = .compactThenTruncateThenDegrade
    ) {
        self.maxRenderedWidth = maxRenderedWidth
        self.minColumnWidth = minColumnWidth
        self.maxColumnWidth = maxColumnWidth
        self.truncationIndicator = truncationIndicator.isEmpty ? "…" : truncationIndicator
        self.overflowBehavior = overflowBehavior
    }
}

public enum TableOverflowBehavior: Sendable, Equatable {
    case degradeImmediately
    case compactThenTruncateThenDegrade
}

public final class PlainTextMarkdownEngine: MarkdownEngine {
    public init() {}

    public func reset() {}

    public func render(text: String, isFinal: Bool) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

public final class StreamingMarkdownEngine: MarkdownEngine {
    private var stableSource = ""
    private var stableRendered: [String] = []
    private let thematicBreak = String(repeating: "─", count: 24)
    public let options: MarkdownRenderOptions

    public init(options: MarkdownRenderOptions = .init()) {
        self.options = options
    }

    public func reset() {
        stableSource = ""
        stableRendered = []
    }

    public func render(text: String, isFinal: Bool) -> [String] {
        guard !text.isEmpty else {
            reset()
            return []
        }

        if !stableSource.isEmpty, !text.hasPrefix(stableSource) {
            reset()
        }

        let suffix = String(text.dropFirst(stableSource.count))
        let advance = stableAdvance(in: suffix, isFinal: isFinal)
        if advance > 0 {
            let stableDelta = String(suffix.prefix(advance))
            stableSource += stableDelta
            var deltaRendered = renderFully(text: stableDelta, isFinal: true)
            let unstable = String(text.dropFirst(stableSource.count))
            if !unstable.isEmpty, stableDelta.hasSuffix("\n"), deltaRendered.last == "" {
                deltaRendered.removeLast()
            }
            stableRendered += deltaRendered
        }

        let unstable = String(text.dropFirst(stableSource.count))
        let unstableRendered = renderFully(text: unstable, isFinal: isFinal)
        return stableRendered + unstableRendered
    }

    private func stableAdvance(in text: String, isFinal: Bool) -> Int {
        guard !text.isEmpty else { return 0 }
        if isFinal { return text.count }
        guard let lastNewline = text.lastIndex(of: "\n") else { return 0 }
        let candidateEnd = text.index(after: lastNewline)
        let candidateText = String(text[..<candidateEnd])

        let lines = candidateText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count >= 3 {
            let trailingEmpty = lines.last == ""
            let dividerIndex = trailingEmpty ? lines.count - 2 : lines.count - 1
            let headerIndex = dividerIndex - 1
            if headerIndex >= 0,
               parseTableCells(lines[headerIndex]) != nil,
               parseDividerCells(lines[dividerIndex]) != nil
            {
                let prefixLines = lines.prefix(headerIndex)
                let prefixText = prefixLines.joined(separator: "\n")
                var retreat = prefixText.count
                if headerIndex > 0 {
                    retreat += 1
                }
                return retreat
            }
        }

        return text.distance(from: text.startIndex, to: candidateEnd)
    }

    private func renderFully(text: String, isFinal: Bool) -> [String] {
        guard !text.isEmpty else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let endsWithNewline = text.hasSuffix("\n")

        var rendered: [String] = []
        var index = 0
        var inCodeFence = false
        while index < lines.count {
            if isCodeFenceDelimiter(lines[index]) {
                if inCodeFence {
                    inCodeFence = false
                    rendered.append(renderCodeFenceEnd())
                } else {
                    inCodeFence = true
                    rendered.append(renderCodeFenceStart(lines[index]))
                }
                index += 1
                continue
            }

            if inCodeFence {
                rendered.append(renderCodeFenceContent(lines[index]))
                index += 1
                continue
            }

            if let table = parseTable(lines: lines, start: index, isFinal: isFinal, endsWithNewline: endsWithNewline) {
                rendered.append(contentsOf: table.lines)
                index += table.consumed
                continue
            }

            rendered.append(renderInlineMarkdown(lines[index]))
            index += 1
        }
        return rendered
    }

    private func parseTable(
        lines: [String],
        start: Int,
        isFinal: Bool,
        endsWithNewline: Bool
    ) -> (lines: [String], consumed: Int)? {
        guard start + 1 < lines.count else { return nil }

        guard let headerCells = parseTableCells(lines[start]) else { return nil }
        guard let divider = parseDividerCells(lines[start + 1]), divider.count == headerCells.count else { return nil }

        var dataRows: [[String]] = []
        var hasMismatchedColumnCount = false
        var cursor = start + 2
        while cursor < lines.count, let cells = parseTableCells(lines[cursor]) {
            if cells.count != headerCells.count {
                hasMismatchedColumnCount = true
            }
            dataRows.append(cells)
            cursor += 1
        }

        guard !dataRows.isEmpty else { return nil }

        if !isFinal, cursor == lines.count, !endsWithNewline {
            return nil
        }

        if hasMismatchedColumnCount {
            let degraded = Array(lines[start..<cursor])
            return (degraded, cursor - start)
        }

        if let rendered = renderTable(header: headerCells, alignment: divider, rows: dataRows) {
            return (rendered, cursor - start)
        }

        let degraded = Array(lines[start..<cursor])
        return (degraded, cursor - start)
    }

    private func isCodeFenceDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private func renderInlineMarkdown(_ line: String) -> String {
        guard !line.isEmpty else { return line }
        return renderStructuredLine(line) ?? line
    }

    private func renderStructuredLine(_ line: String) -> String? {
        let leadingWhitespace = String(line.prefix(while: isIndentationCharacter))
        let trimmed = line.dropFirst(leadingWhitespace.count)
        guard !trimmed.isEmpty else { return nil }

        let (quoteDepth, quoteContent) = parseBlockquotePrefix(trimmed)
        if quoteDepth > 0 {
            let quotePrefix = leadingWhitespace + String(repeating: "│ ", count: quoteDepth)
            let rendered = renderDecoratedContent(
                String(quoteContent),
                indentationLevel: 0,
                rawIndentPrefix: ""
            ) ?? String(quoteContent)
            return rendered.isEmpty ? quotePrefix.trimmingCharacters(in: .whitespaces) : quotePrefix + rendered
        }

        return renderDecoratedContent(
            String(trimmed),
            indentationLevel: indentationUnits(in: leadingWhitespace),
            rawIndentPrefix: leadingWhitespace
        )
    }

    private func renderDecoratedContent(
        _ content: String,
        indentationLevel: Int,
        rawIndentPrefix: String
    ) -> String? {
        let leadingWhitespace = String(content.prefix(while: isIndentationCharacter))
        let trimmed = content.dropFirst(leadingWhitespace.count)
        guard !trimmed.isEmpty else { return nil }

        let totalIndentationLevel = indentationLevel + indentationUnits(in: leadingWhitespace)
        let normalizedIndent = String(repeating: "  ", count: totalIndentationLevel)
        let body = String(trimmed)

        if let heading = renderHeading(body) {
            return rawIndentPrefix + leadingWhitespace + heading
        }
        if let listItem = renderListItem(body, nestingLevel: totalIndentationLevel) {
            return normalizedIndent + listItem
        }
        if isThematicBreak(body) {
            return rawIndentPrefix + leadingWhitespace + thematicBreak
        }
        return nil
    }

    private func renderHeading(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }

        let markerCount = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(markerCount) else { return nil }
        guard trimmed.count > markerCount else { return nil }

        let markerEnd = trimmed.index(trimmed.startIndex, offsetBy: markerCount)
        guard trimmed[markerEnd] == " " else { return nil }

        let title = trimmed[trimmed.index(after: markerEnd)...].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        let prefix: String
        switch markerCount {
        case 1: prefix = "█ "
        case 2: prefix = "▓ "
        case 3: prefix = "▶ "
        case 4: prefix = "▹ "
        case 5: prefix = "• "
        default: prefix = "· "
        }
        return prefix + title
    }

    private func parseBlockquotePrefix(_ content: Substring) -> (depth: Int, remainder: Substring) {
        guard content.first == ">" else { return (0, content) }

        var index = content.startIndex
        var depth = 0
        while index < content.endIndex, content[index] == ">" {
            depth += 1
            index = content.index(after: index)
            if index < content.endIndex, content[index] == " " {
                index = content.index(after: index)
            }
        }
        return (depth, content[index...])
    }

    private func renderListItem(_ line: String, nestingLevel: Int) -> String? {
        let trimmed = line[...]
        guard !trimmed.isEmpty else { return nil }

        if let marker = trimmed.first, (marker == "-" || marker == "+" || marker == "*") {
            let nextIndex = trimmed.index(after: trimmed.startIndex)
            guard nextIndex < trimmed.endIndex, trimmed[nextIndex] == " " else { return nil }
            let content = String(trimmed[trimmed.index(after: nextIndex)...])
            return "\(unorderedListBullet(for: nestingLevel)) \(content)"
        }

        let digits = trimmed.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        guard digits.endIndex < trimmed.endIndex else { return nil }
        let separator = trimmed[digits.endIndex]
        guard separator == "." || separator == ")" else { return nil }
        let contentStart = trimmed.index(after: digits.endIndex)
        guard contentStart < trimmed.endIndex, trimmed[contentStart] == " " else { return nil }
        let content = String(trimmed[trimmed.index(after: contentStart)...])
        return "\(digits). \(content)"
    }

    private func unorderedListBullet(for nestingLevel: Int) -> String {
        let bullets = ["•", "◦", "▪", "▫"]
        let index = max(0, nestingLevel) % bullets.count
        return bullets[index]
    }

    private func indentationUnits(in whitespace: String) -> Int {
        let width = whitespace.reduce(into: 0) { partialResult, character in
            partialResult += character == "\t" ? 4 : 1
        }
        return max(0, width / 2)
    }

    private func isIndentationCharacter(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }

    private func isThematicBreak(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        let uniqueCharacters = Set(trimmed)
        guard uniqueCharacters.count == 1, let character = uniqueCharacters.first else { return false }
        return character == "-" || character == "*" || character == "_"
    }

    private func renderCodeFenceStart(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let language = trimmed.drop(while: { $0 == "`" || $0 == "~" }).trimmingCharacters(in: .whitespaces)
        return language.isEmpty ? "┌─ code" : "┌─ code \(language)"
    }

    private func renderCodeFenceEnd() -> String {
        "└─ end code"
    }

    private func renderCodeFenceContent(_ line: String) -> String {
        line.isEmpty ? "│" : "│ \(line)"
    }

    private func splitRowCells(_ body: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var isEscaped = false
        var inCodeSpan = false

        for character in body {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if character == "`" {
                inCodeSpan.toggle()
                current.append(character)
                continue
            }

            if character == "|", !inCodeSpan {
                cells.append(current)
                current.removeAll(keepingCapacity: true)
                continue
            }

            current.append(character)
        }

        if isEscaped {
            current.append("\\")
        }

        cells.append(current)
        return cells
    }

    private func hasUnescapedPipe(_ text: String) -> Bool {
        var isEscaped = false
        var inCodeSpan = false

        for character in text {
            if isEscaped {
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if character == "`" {
                inCodeSpan.toggle()
                continue
            }
            if character == "|", !inCodeSpan {
                return true
            }
        }
        return false
    }

    private func resolvedColumnWidths(
        idealWidths: [Int],
        columnCount: Int,
        policy: TableRenderPolicy
    ) -> [Int]? {
        guard !idealWidths.isEmpty, idealWidths.count == columnCount else { return nil }

        switch policy.overflowBehavior {
        case .degradeImmediately:
            return shouldDegradeWideTable(widths: idealWidths, maxRenderedWidth: policy.maxRenderedWidth)
                ? nil
                : idealWidths
        case .compactThenTruncateThenDegrade:
            let minimumWidth = max(1, policy.minColumnWidth)
            let maxContentWidth = policy.maxRenderedWidth - tableChromeWidth(for: columnCount)
            guard maxContentWidth >= minimumWidth * columnCount else { return nil }

            var widths = idealWidths.map { width in
                let clamped = max(minimumWidth, width)
                if let maxColumnWidth = policy.maxColumnWidth {
                    return min(clamped, max(maxColumnWidth, minimumWidth))
                }
                return clamped
            }

            var totalWidth = widths.reduce(0, +)
            while totalWidth > maxContentWidth {
                guard let widestIndex = widestShrinkableColumn(in: widths, minimumWidth: minimumWidth) else {
                    return nil
                }
                widths[widestIndex] -= 1
                totalWidth -= 1
            }

            return widths
        }
    }

    private func widestShrinkableColumn(in widths: [Int], minimumWidth: Int) -> Int? {
        var widestIndex: Int?
        var widestValue = minimumWidth

        for (index, width) in widths.enumerated() where width > widestValue {
            widestValue = width
            widestIndex = index
        }

        return widestIndex
    }

    private func tableChromeWidth(for columnCount: Int) -> Int {
        columnCount * 3 + 1
    }

    private func shouldDegradeWideTable(widths: [Int], maxRenderedWidth: Int) -> Bool {
        let renderedWidth = visibleWidth(borderLine(left: "┌", middle: "┬", right: "┐", widths: widths))
        return renderedWidth > maxRenderedWidth
    }

    private func parseTableCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard hasUnescapedPipe(trimmed), !trimmed.isEmpty else { return nil }

        var body = trimmed
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }

        let cells = splitRowCells(body)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        return cells.count >= 2 ? cells : nil
    }

    private func parseDividerCells(_ line: String) -> [CellAlign]? {
        guard let cells = parseTableCells(line), !cells.isEmpty else { return nil }
        var aligns: [CellAlign] = []
        for cell in cells {
            let value = cell.trimmingCharacters(in: .whitespaces)
            let core = value.replacingOccurrences(of: ":", with: "")
            guard core.count >= 3, core.allSatisfy({ $0 == "-" }) else { return nil }

            if value.hasPrefix(":"), value.hasSuffix(":") {
                aligns.append(.center)
            } else if value.hasSuffix(":") {
                aligns.append(.right)
            } else {
                aligns.append(.left)
            }
        }
        return aligns
    }

    private func renderTable(header: [String], alignment: [CellAlign], rows: [[String]]) -> [String]? {
        let normalizedRows = rows.map { normalize(cells: $0, count: header.count) }
        var widths = Array(repeating: 0, count: header.count)

        for col in 0..<header.count {
            widths[col] = max(widths[col], visibleWidth(header[col]))
            for row in normalizedRows {
                widths[col] = max(widths[col], visibleWidth(row[col]))
            }
            widths[col] = max(widths[col], 1)
        }

        guard let resolvedWidths = resolvedColumnWidths(
            idealWidths: widths,
            columnCount: header.count,
            policy: options.tablePolicy
        ) else {
            return nil
        }

        var output: [String] = []
        output.append(borderLine(left: "┌", middle: "┬", right: "┐", widths: resolvedWidths))
        output.append(tableRow(cells: header, aligns: alignment, widths: resolvedWidths, policy: options.tablePolicy))
        output.append(borderLine(left: "├", middle: "┼", right: "┤", widths: resolvedWidths))
        for row in normalizedRows {
            output.append(tableRow(cells: row, aligns: alignment, widths: resolvedWidths, policy: options.tablePolicy))
        }
        output.append(borderLine(left: "└", middle: "┴", right: "┘", widths: resolvedWidths))
        return output
    }

    private enum CellAlign {
        case left
        case center
        case right
    }

    private func normalize(cells: [String], count: Int) -> [String] {
        if cells.count == count { return cells }
        if cells.count > count { return Array(cells.prefix(count)) }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    private func borderLine(left: String, middle: String, right: String, widths: [Int]) -> String {
        let segments = widths.map { String(repeating: "─", count: $0 + 2) }
        return left + segments.joined(separator: middle) + right
    }

    private func tableRow(cells: [String], aligns: [CellAlign], widths: [Int], policy: TableRenderPolicy) -> String {
        var parts: [String] = []
        for index in 0..<cells.count {
            parts.append(padded(cells[index], width: widths[index], align: aligns[index], policy: policy))
        }
        return "│ " + parts.joined(separator: " │ ") + " │"
    }

    private func padded(_ value: String, width: Int, align: CellAlign, policy: TableRenderPolicy) -> String {
        let fittedValue = truncate(value, toFit: width, indicator: policy.truncationIndicator)
        let textWidth = visibleWidth(fittedValue)
        let gap = max(0, width - textWidth)

        switch align {
        case .left:
            return fittedValue + String(repeating: " ", count: gap)
        case .right:
            return String(repeating: " ", count: gap) + fittedValue
        case .center:
            let left = gap / 2
            let right = gap - left
            return String(repeating: " ", count: left) + fittedValue + String(repeating: " ", count: right)
        }
    }

    private func truncate(_ value: String, toFit maxWidth: Int, indicator: String) -> String {
        guard maxWidth > 0 else { return "" }
        guard visibleWidth(value) > maxWidth else { return value }

        let indicatorWidth = min(maxWidth, visibleWidth(indicator))
        if indicatorWidth >= maxWidth {
            return fittingPrefix(of: indicator, maxWidth: maxWidth)
        }

        let prefixWidth = maxWidth - indicatorWidth
        return fittingPrefix(of: value, maxWidth: prefixWidth) + indicator
    }

    private func fittingPrefix(of value: String, maxWidth: Int) -> String {
        guard maxWidth > 0 else { return "" }
        var result = ""
        var currentWidth = 0

        for character in value {
            let characterWidth = visibleWidth(String(character))
            if currentWidth + characterWidth > maxWidth {
                break
            }
            result.append(character)
            currentWidth += characterWidth
        }

        return result
    }
}
