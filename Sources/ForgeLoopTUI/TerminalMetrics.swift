import Foundation

public func ansiStripped(_ text: String) -> String {
    var result = ""
    var index = text.startIndex
    while index < text.endIndex {
        let char = text[index]
        if char == "\u{1B}" {
            let next = text.index(after: index)
            if next < text.endIndex, text[next] == "[" {
                var paramIndex = text.index(after: next)
                while paramIndex < text.endIndex {
                    let paramChar = text[paramIndex]
                    if (0x40...0x7E).contains(paramChar.asciiValue ?? 0) {
                        index = text.index(after: paramIndex)
                        break
                    }
                    paramIndex = text.index(after: paramIndex)
                }
                if paramIndex >= text.endIndex {
                    break
                }
                continue
            }
        }
        result.append(char)
        index = text.index(after: index)
    }
    return result
}

public func visibleWidth(_ text: String) -> Int {
    let stripped = ansiStripped(text)
    var width = 0
    for scalar in stripped.unicodeScalars {
        let value = scalar.value
        if value < 0x20 || value == 0x7F {
            continue
        }
        if value < 0x7F {
            width += 1
            continue
        }
        let isWide = (0x1100...0x115F).contains(value)
            || (0x2329...0x232A).contains(value)
            || (0x2E80...0x303E).contains(value)
            || (0x3041...0xA4C6).contains(value)
            || (0xAC00...0xD7A3).contains(value)
            || (0xF900...0xFAFF).contains(value)
            || (0xFE10...0xFE6B).contains(value)
            || (0xFF01...0xFF60).contains(value)
            || (0xFFE0...0xFFE6).contains(value)
            || (0x1F300...0x1F64F).contains(value)
            || (0x1F680...0x1F9FF).contains(value)
            || (0x20000...0x2FFFD).contains(value)
            || (0x30000...0x3FFFD).contains(value)
        width += isWide ? 2 : 1
    }
    return width
}

public func physicalRows(for line: String, width: Int) -> Int {
    guard width > 0 else { return 1 }
    let vw = visibleWidth(line)
    if vw == 0 { return 1 }
    return (vw + width - 1) / width
}
