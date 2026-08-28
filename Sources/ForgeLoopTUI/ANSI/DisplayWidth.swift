import Foundation

/// Returns `text` with ANSI CSI escape sequences removed.
///
/// A CSI sequence spans `ESC [`, any parameter/intermediate bytes, and one
/// final byte in `0x40...0x7E`. An unterminated trailing CSI is dropped
/// together with the remainder of the string; other escape sequences are
/// preserved verbatim. Useful when measuring or laying out styled text.
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

/// The number of terminal cells `text` occupies when rendered.
///
/// ANSI CSI sequences are stripped first (see ``ansiStripped(_:)``), then the
/// remaining text is measured per grapheme cluster: ASCII control characters
/// and combining marks count 0, wide scalars (CJK, fullwidth forms, most
/// emoji) count 2, and multi-scalar clusters that render as a single glyph —
/// ZWJ sequences, skin-tone modifiers, VS16 emoji presentation, RI flag
/// pairs — count 2 as a whole. Everything else counts 1.
public func visibleWidth(_ text: String) -> Int {
    let stripped = ansiStripped(text)
    // Fast path: pure ASCII has no grapheme-cluster subtleties — every
    // printable scalar occupies exactly one cell.
    var asciiWidth = 0
    var needsClusterSemantics = false
    for scalar in stripped.unicodeScalars {
        let value = scalar.value
        if value >= 0x80 {
            needsClusterSemantics = true
            break
        }
        if value < 0x20 || value == 0x7F {
            continue
        }
        asciiWidth += 1
    }
    if !needsClusterSemantics {
        return asciiWidth
    }
    var width = 0
    for character in stripped {
        width += graphemeClusterWidth(character)
    }
    return width
}

/// 单个 grapheme cluster(`Character`)的可见宽度,按终端 wcwidth 语义在
/// cluster 粒度上计宽:
///
/// - C0/DEL 控制符计 0,其余 ASCII 计 1;
/// - 组合附加符(Mn/Me)与 variation selector 单独出现时计 0;
/// - 宽 scalar(CJK、全角、多数 emoji,见 ``scalarIsWide``)计 2,其余计 1;
/// - 多 scalar cluster 整体计一次:ZWJ 序列(👨‍👩‍👧‍👦)、肤色修饰(👍🏽)、
///   VS16 emoji 呈现(❤️)、国旗 RI 对(🇨🇳)均为 2 格,而非各 scalar 之和。
///
/// `visibleWidth` 与 `MultiLineInputState` 的视觉导航共享此判定,
/// 保证光标计算与布局计算对同一 cluster 的宽度永不分歧。
func graphemeClusterWidth(_ character: Character) -> Int {
    let scalars = character.unicodeScalars
    // Fast path: single scalar (covers ASCII, CJK, plain emoji, lone marks).
    if scalars.count == 1, let scalar = scalars.first {
        return scalarCellWidth(scalar)
    }
    var rendersAsSingleWideGlyph = false
    var maxScalarWidth = 0
    for scalar in scalars {
        let value = scalar.value
        // ZWJ、regional indicator、VS16 出现的 cluster 在终端渲染为单个
        // 2 格字形。
        if value == 0x200D
            || value == 0xFE0F
            || (0x1F1E6...0x1F1FF).contains(value) {
            rendersAsSingleWideGlyph = true
        }
        maxScalarWidth = max(maxScalarWidth, scalarCellWidth(scalar))
    }
    // 肤色修饰符(U+1F3FB...U+1F3FF)无需特判:基础 emoji 与修饰符都是宽
    // scalar,`maxScalarWidth` 已是 2(如 👍🏽)。
    return rendersAsSingleWideGlyph ? 2 : maxScalarWidth
}

/// 单一 scalar 的可见宽度;cluster 语义由 ``graphemeClusterWidth`` 负责。
private func scalarCellWidth(_ scalar: Unicode.Scalar) -> Int {
    let value = scalar.value
    if value < 0x20 || value == 0x7F {
        return 0
    }
    if value < 0x7F {
        return 1
    }
    // 组合附加符(Mn/Me,含 VS16 U+FE0F)自身不占格。
    let category = scalar.properties.generalCategory
    if category == .nonspacingMark || category == .enclosingMark {
        return 0
    }
    return scalarIsWide(value) ? 2 : 1
}

/// 单一 Unicode scalar 是否为宽字符（CJK / emoji / 全角符号等）。
/// 基准：Unicode 16.0 的 EastAsianWidth(W/F) ∪ Emoji_Presentation，
/// 并保留旧表全部既有宽区间（仅增不减，避免既有文本重排回归）。
/// ``graphemeClusterWidth`` 用它判定 cluster 内各 scalar 的基础宽度。
func scalarIsWide(_ value: UInt32) -> Bool {
    (0x1100...0x115F).contains(value)
        || (0x231A...0x231B).contains(value)
        || (0x2329...0x232A).contains(value)
        || (0x23E9...0x23EC).contains(value)
        || (0x23F0...0x23F0).contains(value)
        || (0x23F3...0x23F3).contains(value)
        || (0x25FD...0x25FE).contains(value)
        || (0x2614...0x2615).contains(value)
        || (0x2630...0x2637).contains(value)
        || (0x2648...0x2653).contains(value)
        || (0x267F...0x267F).contains(value)
        || (0x268A...0x268F).contains(value)
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
        || (0x2757...0x2757).contains(value)
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
        || (0x3190...0x31E5).contains(value)
        || (0x31EF...0x321E).contains(value)
        || (0x3220...0x3247).contains(value)
        || (0x3250...0xA48C).contains(value)
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
        || (0x1F004...0x1F004).contains(value)
        || (0x1F0CF...0x1F0CF).contains(value)
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
        || (0x1F6D5...0x1F6D7).contains(value)
        || (0x1F6DC...0x1F6DF).contains(value)
        || (0x1F6EB...0x1F6EC).contains(value)
        || (0x1F6F4...0x1F6FC).contains(value)
        || (0x1F7E0...0x1F7EB).contains(value)
        || (0x1F7F0...0x1F7F0).contains(value)
        || (0x1F90C...0x1F9FF).contains(value)
        || (0x1FA70...0x1FA7C).contains(value)
        || (0x1FA80...0x1FA89).contains(value)
        || (0x1FA8F...0x1FAC6).contains(value)
        || (0x1FACE...0x1FADC).contains(value)
        || (0x1FADF...0x1FAE9).contains(value)
        || (0x1FAF0...0x1FAF8).contains(value)
        || (0x20000...0x2FFFD).contains(value)
        || (0x30000...0x3FFFD).contains(value)
}

public func physicalRows(for line: String, width: Int) -> Int {
    guard width > 0 else { return 1 }
    let vw = visibleWidth(line)
    if vw == 0 { return 1 }
    return (vw + width - 1) / width
}
