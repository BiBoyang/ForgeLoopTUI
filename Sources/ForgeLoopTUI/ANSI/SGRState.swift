import Foundation

/// SGR（Select Graphic Rendition）状态模型。
///
/// 支持的代码：
/// - `0`       reset
/// - `1`       bold
/// - `2`       dim
/// - `22`      normal intensity（取消 bold / dim）
/// - `30-37`   标准前景色
/// - `39`      默认前景色
/// - `40-47`   标准背景色
/// - `49`      默认背景色
/// - `90-97`   高亮前景色
/// - `100-107` 高亮背景色
/// - `38;5;n` / `48;5;n`     256 色（indexed）
/// - `38;2;r;g;b` / `48;2;r;g;b`  24-bit True Color（rgb）
///
/// 安全语义：扩展颜色参数不完整时不修改已有状态。
public struct SGRState: Sendable, Equatable {
    public var bold: Bool = false
    public var dim: Bool = false
    public var foreground: Color? = nil
    public var background: Color? = nil

    public init() {}

    /// 应用一组 SGR 参数码。
    public mutating func apply(_ params: [Int]) {
        guard !params.isEmpty else {
            reset()
            return
        }
        var i = 0
        while i < params.count {
            let code = params[i]
            switch code {
            case 0:
                reset()
            case 1:
                bold = true
            case 2:
                dim = true
            case 22:
                bold = false
                dim = false
            case 30...37:
                foreground = .standard(code - 30)
            case 39:
                foreground = nil
            case 40...47:
                background = .standard(code - 40)
            case 49:
                background = nil
            case 90...97:
                foreground = .bright(code - 90)
            case 100...107:
                background = .bright(code - 100)
            case 38:
                // 前景扩展颜色：38;5;n 或 38;2;r;g;b
                if i + 1 < params.count {
                    if params[i + 1] == 5 {
                        if i + 2 < params.count {
                            foreground = .indexed(params[i + 2])
                        }
                        i += 2
                    } else if params[i + 1] == 2 {
                        if i + 4 < params.count {
                            foreground = .rgb(params[i + 2], params[i + 3], params[i + 4])
                        }
                        i += 4
                    }
                }
            case 48:
                // 背景扩展颜色：48;5;n 或 48;2;r;g;b
                if i + 1 < params.count {
                    if params[i + 1] == 5 {
                        if i + 2 < params.count {
                            background = .indexed(params[i + 2])
                        }
                        i += 2
                    } else if params[i + 1] == 2 {
                        if i + 4 < params.count {
                            background = .rgb(params[i + 2], params[i + 3], params[i + 4])
                        }
                        i += 4
                    }
                }
            default:
                break
            }
            i += 1
        }
    }

    public mutating func reset() {
        bold = false
        dim = false
        foreground = nil
        background = nil
    }
}

public enum Color: Sendable, Equatable {
    /// 标准 8 色（0–7）。
    case standard(Int)
    /// 高亮 8 色（0–7）。
    case bright(Int)
    /// 256 色索引（0–255）。
    case indexed(Int)
    /// 24-bit True Color。
    case rgb(Int, Int, Int)

    /// 根据终端能力生成 SGR 参数码序列。
    func sgrCodes(isBackground: Bool, capability: TerminalCapability) -> [Int] {
        let base = isBackground ? 40 : 30
        let brightBase = isBackground ? 100 : 90
        let extBase = isBackground ? 48 : 38

        switch self {
        case .standard(let n):
            return [base + n]
        case .bright(let n):
            return [brightBase + n]
        case .indexed(let n):
            switch capability {
            case .plain, .ansi16:
                return Self.nearestStandard(indexed: n).sgrCodes(isBackground: isBackground, capability: capability)
            case .ansi256, .truecolor:
                return [extBase, 5, n]
            }
        case .rgb(let r, let g, let b):
            switch capability {
            case .plain, .ansi16:
                let idx = Self.nearestIndexed(r: r, g: g, b: b)
                return Self.indexed(idx).sgrCodes(isBackground: isBackground, capability: capability)
            case .ansi256:
                let idx = Self.nearestIndexed(r: r, g: g, b: b)
                return [extBase, 5, idx]
            case .truecolor:
                return [extBase, 2, r, g, b]
            }
        }
    }

    // MARK: - Private

    private static func nearestIndexed(r: Int, g: Int, b: Int) -> Int {
        if abs(r - g) < 5 && abs(g - b) < 5 && abs(r - b) < 5 {
            let avg = (r + g + b) / 3
            if avg < 8 { return 16 }
            if avg > 238 { return 231 }
            return 232 + min(23, (avg - 8) / 10)
        }
        let ri = min(5, max(0, Int(round(Double(r) * 5.0 / 255.0))))
        let gi = min(5, max(0, Int(round(Double(g) * 5.0 / 255.0))))
        let bi = min(5, max(0, Int(round(Double(b) * 5.0 / 255.0))))
        return 16 + ri * 36 + gi * 6 + bi
    }

    private static func nearestStandard(indexed: Int) -> Color {
        if indexed < 16 {
            return indexed < 8 ? .standard(indexed) : .bright(indexed - 8)
        }
        if indexed >= 232 {
            let gray = indexed - 232
            return gray < 12 ? .standard(0) : .standard(7)
        }
        let n = indexed - 16
        let r = (n / 36) * 51
        let g = ((n % 36) / 6) * 51
        let b = (n % 6) * 51
        return nearestStandard(r: r, g: g, b: b)
    }

    private static func nearestStandard(r: Int, g: Int, b: Int) -> Color {
        let palette: [(Color, Int, Int, Int)] = [
            (.standard(0), 0, 0, 0),
            (.standard(1), 170, 0, 0),
            (.standard(2), 0, 170, 0),
            (.standard(3), 170, 85, 0),
            (.standard(4), 0, 0, 170),
            (.standard(5), 170, 0, 170),
            (.standard(6), 0, 170, 170),
            (.standard(7), 170, 170, 170),
        ]
        var best = palette[0].0
        var bestDist = Int.max
        for (color, cr, cg, cb) in palette {
            let dist = (r - cr) * (r - cr) + (g - cg) * (g - cg) + (b - cb) * (b - cb)
            if dist < bestDist {
                bestDist = dist
                best = color
            }
        }
        return best
    }
}
