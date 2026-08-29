import Foundation

// MARK: - SGR primitives

/// A terminal color expressed as SGR (Select Graphic Rendition) parameters.
///
/// The cases cover the ANSI 16-color palette (`standard` / `bright`), the
/// 256-color palette (`indexed`), and 24-bit color (`rgb`). Parameter ranges
/// are the caller's responsibility: out-of-range values compile but emit SGR
/// sequences a terminal is free to ignore.
public enum MarkdownSGRColor: Sendable, Equatable {
    /// A basic ANSI palette color, `0...7` (black, red, green, yellow, blue,
    /// magenta, cyan, white).
    case standard(Int)
    /// A bright ANSI palette color, `0...7`.
    case bright(Int)
    /// A 256-color palette index, `0...255`.
    case indexed(Int)
    /// A 24-bit direct color.
    case rgb(red: UInt8, green: UInt8, blue: UInt8)

    /// The SGR parameter codes selecting this color, for a foreground
    /// (`isBackground == false`) or background slot.
    public func sgrParameters(isBackground: Bool) -> [Int] {
        switch self {
        case .standard(let n):
            return [(isBackground ? 40 : 30) + n]
        case .bright(let n):
            return [(isBackground ? 100 : 90) + n]
        case .indexed(let n):
            return isBackground ? [48, 5, n] : [38, 5, n]
        case .rgb(let red, let green, let blue):
            return isBackground
                ? [48, 2, Int(red), Int(green), Int(blue)]
                : [38, 2, Int(red), Int(green), Int(blue)]
        }
    }
}

/// A single SGR (Select Graphic Rendition) attribute — the styling primitive
/// `MarkdownStyle` and `MarkdownTheme` slots are built from.
public enum MarkdownSGRAttribute: Sendable, Equatable {
    /// Bold intensity (SGR 1).
    case bold
    /// Faint / dim intensity (SGR 2).
    case faint
    /// Italic (SGR 3).
    case italic
    /// Underline (SGR 4).
    case underline
    /// Inverse video (SGR 7).
    case inverse
    /// Strikethrough (SGR 9).
    case strikethrough
    /// Foreground text color.
    case foreground(MarkdownSGRColor)
    /// Background color.
    case background(MarkdownSGRColor)

    /// The raw SGR parameter codes for this attribute, e.g. `[1]` for bold or
    /// `[38, 5, 208]` for an indexed foreground color.
    public var parameters: [Int] {
        switch self {
        case .bold: return [1]
        case .faint: return [2]
        case .italic: return [3]
        case .underline: return [4]
        case .inverse: return [7]
        case .strikethrough: return [9]
        case .foreground(let color): return color.sgrParameters(isBackground: false)
        case .background(let color): return color.sgrParameters(isBackground: true)
        }
    }
}

/// An ordered combination of SGR attributes that wraps text in a single
/// escape sequence pair: `ESC[<parameters>m` + text + `ESC[0m`.
///
/// Purely functional value type — no environment probing, no capability
/// negotiation. Deciding *whether* to emit ANSI at all is the rendering
/// engine's job; a style only describes *what* to emit.
public struct MarkdownStyle: Sendable, Equatable {
    /// The attributes applied left to right; duplicates are preserved as given
    /// and later attributes override earlier ones on the terminal side.
    public var attributes: [MarkdownSGRAttribute]

    /// The style that leaves text untouched.
    public static let none = MarkdownStyle()

    public init(_ attributes: [MarkdownSGRAttribute] = []) {
        self.attributes = attributes
    }

    /// `true` when this style carries no attributes and `applied(to:)` is the
    /// identity function.
    public var isEmpty: Bool { attributes.isEmpty }

    /// Wraps `text` with this style's SGR sequence and a trailing reset.
    ///
    /// Empty styles and empty text pass through unchanged (no escape bytes),
    /// so engines can apply styles unconditionally without polluting blank
    /// lines or unstyled output.
    public func applied(to text: String) -> String {
        guard !attributes.isEmpty, !text.isEmpty else { return text }
        let parameters = attributes.flatMap(\.parameters).map(String.init).joined(separator: ";")
        return "\u{1B}[\(parameters)m\(text)\u{1B}[0m"
    }
}

// MARK: - Theme

/// Visual theme for markdown block-level chrome: heading levels, table header
/// and borders, the blockquote bar, code-fence borders and language labels,
/// task-list markers, and syntax-highlight categories for fence content.
///
/// A theme is a plain value type injected through `MarkdownRenderOptions.theme`
/// — never a singleton or global — so rendering stays a deterministic function
/// of the input text plus options (the stable-prefix commit contract).
///
/// Two presets ship:
/// - ``default``: styled slots for every element (the default).
/// - ``none``: every slot empty, pinning the pre-theme plain-text byte stream.
public struct MarkdownTheme: Sendable, Equatable {
    /// Heading level 1 style.
    public var heading1: MarkdownStyle
    /// Heading level 2 style.
    public var heading2: MarkdownStyle
    /// Heading level 3 style.
    public var heading3: MarkdownStyle
    /// Heading level 4 style.
    public var heading4: MarkdownStyle
    /// Heading level 5 style.
    public var heading5: MarkdownStyle
    /// Heading level 6 style.
    public var heading6: MarkdownStyle
    /// Table header row (cell text).
    public var tableHeader: MarkdownStyle
    /// Table border lines and junction characters.
    public var tableBorder: MarkdownStyle
    /// The blockquote vertical bar (`│`).
    public var blockquoteLine: MarkdownStyle
    /// Code-fence border lines.
    public var fenceBorder: MarkdownStyle
    /// The language label shown on the opening fence border.
    public var fenceLanguageLabel: MarkdownStyle
    /// Checked task-list marker (`☑`).
    public var taskListChecked: MarkdownStyle
    /// Unchecked task-list marker (`☐`).
    public var taskListUnchecked: MarkdownStyle
    /// Styles for syntax-highlighted fence content.
    public var code: CodeHighlightStyles

    /// The styled built-in theme: bold colored headings, bold table header,
    /// dimmed chrome (borders, quote bar, fence borders, language label),
    /// colored task markers, and ANSI-16 code categories.
    public static let `default` = MarkdownTheme(
        heading1: MarkdownStyle([.bold, .foreground(.bright(4))]),
        heading2: MarkdownStyle([.bold, .foreground(.standard(4))]),
        heading3: MarkdownStyle([.bold, .foreground(.standard(6))]),
        heading4: MarkdownStyle([.bold]),
        heading5: MarkdownStyle([.bold, .foreground(.bright(0))]),
        heading6: MarkdownStyle([.foreground(.bright(0))]),
        tableHeader: MarkdownStyle([.bold]),
        tableBorder: MarkdownStyle([.faint]),
        blockquoteLine: MarkdownStyle([.faint]),
        fenceBorder: MarkdownStyle([.faint]),
        fenceLanguageLabel: MarkdownStyle([.faint, .italic]),
        taskListChecked: MarkdownStyle([.foreground(.standard(2))]),
        taskListUnchecked: MarkdownStyle([.foreground(.bright(0))]),
        code: CodeHighlightStyles(
            keyword: MarkdownStyle([.foreground(.standard(3))]),
            string: MarkdownStyle([.foreground(.standard(2))]),
            comment: MarkdownStyle([.faint]),
            number: MarkdownStyle([.foreground(.standard(6))])
        )
    )

    /// The plain-text theme: every slot empty, so themed elements render with
    /// no escape bytes — byte-identical to pre-theme output.
    public static let none = MarkdownTheme(
        heading1: .none,
        heading2: .none,
        heading3: .none,
        heading4: .none,
        heading5: .none,
        heading6: .none,
        tableHeader: .none,
        tableBorder: .none,
        blockquoteLine: .none,
        fenceBorder: .none,
        fenceLanguageLabel: .none,
        taskListChecked: .none,
        taskListUnchecked: .none,
        code: CodeHighlightStyles(
            keyword: .none,
            string: .none,
            comment: .none,
            number: .none
        )
    )

    public init(
        heading1: MarkdownStyle = MarkdownTheme.default.heading1,
        heading2: MarkdownStyle = MarkdownTheme.default.heading2,
        heading3: MarkdownStyle = MarkdownTheme.default.heading3,
        heading4: MarkdownStyle = MarkdownTheme.default.heading4,
        heading5: MarkdownStyle = MarkdownTheme.default.heading5,
        heading6: MarkdownStyle = MarkdownTheme.default.heading6,
        tableHeader: MarkdownStyle = MarkdownTheme.default.tableHeader,
        tableBorder: MarkdownStyle = MarkdownTheme.default.tableBorder,
        blockquoteLine: MarkdownStyle = MarkdownTheme.default.blockquoteLine,
        fenceBorder: MarkdownStyle = MarkdownTheme.default.fenceBorder,
        fenceLanguageLabel: MarkdownStyle = MarkdownTheme.default.fenceLanguageLabel,
        taskListChecked: MarkdownStyle = MarkdownTheme.default.taskListChecked,
        taskListUnchecked: MarkdownStyle = MarkdownTheme.default.taskListUnchecked,
        code: CodeHighlightStyles = MarkdownTheme.default.code
    ) {
        self.heading1 = heading1
        self.heading2 = heading2
        self.heading3 = heading3
        self.heading4 = heading4
        self.heading5 = heading5
        self.heading6 = heading6
        self.tableHeader = tableHeader
        self.tableBorder = tableBorder
        self.blockquoteLine = blockquoteLine
        self.fenceBorder = fenceBorder
        self.fenceLanguageLabel = fenceLanguageLabel
        self.taskListChecked = taskListChecked
        self.taskListUnchecked = taskListUnchecked
        self.code = code
    }

    /// The heading style for `level`, clamped into `1...6` (levels below 1 map
    /// to level 1, levels above 6 to level 6).
    public func headingStyle(forLevel level: Int) -> MarkdownStyle {
        switch level {
        case ...1: return heading1
        case 2: return heading2
        case 3: return heading3
        case 4: return heading4
        case 5: return heading5
        default: return heading6
        }
    }

    /// Syntax-highlight styles for code inside fences. The category set is
    /// intentionally minimal (keyword / string / comment / number); categories
    /// may be added in minor releases as more languages are highlighted.
    public struct CodeHighlightStyles: Sendable, Equatable {
        /// Language keywords and declarations.
        public var keyword: MarkdownStyle
        /// String and character literals (including template strings).
        public var string: MarkdownStyle
        /// Comments (line and block).
        public var comment: MarkdownStyle
        /// Numeric literals.
        public var number: MarkdownStyle

        public init(
            keyword: MarkdownStyle = .none,
            string: MarkdownStyle = .none,
            comment: MarkdownStyle = .none,
            number: MarkdownStyle = .none
        ) {
            self.keyword = keyword
            self.string = string
            self.comment = comment
            self.number = number
        }
    }
}
