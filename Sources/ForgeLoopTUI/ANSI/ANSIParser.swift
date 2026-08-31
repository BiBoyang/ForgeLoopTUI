/// ANSI byte-stream state machine: splits input text into plain text events and
/// CSI control-sequence events.
///
/// Design goals:
/// - Support CSI sequences fragmented across `write()` calls.
/// - Minimal: recognizes only text and CSI, with no styling semantics.
/// - OSC sequences (`ESC ] …`, e.g. OSC 8 hyperlinks) are swallowed whole —
///   terminated by BEL or ST (`ESC \`) — matching how a real terminal absorbs
///   them without displaying the payload.
/// - Reusable by consumers such as `VirtualTerminal`.
public struct ANSIParser: Sendable {
    public enum Event: Sendable {
        /// A visible (or control) character.
        case text(Character)
        /// A fully parsed CSI sequence.
        ///
        /// `intermediates` is the concatenated string of intermediate bytes (0x20–0x2F); empty for the vast majority of CSI sequences.
        /// In `params`, `:` sub-parameters are flattened by the same rule as `;`; empty parameters are recorded as 0 per the ECMA-48
        /// convention (0 = the parameter's default value), with concrete defaults mapped per command by the consumer.
        case csi(params: [Int], intermediates: String, command: Character)
    }

    private enum State: Sendable {
        case ground
        case escape
        case csiEntry
        case csiParam
        case csiIntermediate
        /// Inside an OSC sequence (`ESC ] …`); payload is swallowed.
        case osc
        /// Inside OSC after an ESC: `\` ends the sequence (ST), anything
        /// else resumes the OSC payload.
        case oscEscape
    }

    private var state: State = .ground
    private var paramBuffer: String = ""
    private var intermediateBuffer: String = ""

    public init() {}

    /// Feeds a single Unicode scalar, emitting events via the `emit` callback.
    ///
    /// If the current scalar belongs to an unfinished CSI sequence, no event is
    /// emitted; the state is retained so the next `feed` call can continue assembling it.
    public mutating func feed(_ scalar: Unicode.Scalar, emit: (Event) -> Void) {
        switch state {
        case .ground:
            if scalar == "\u{1B}" {
                state = .escape
            } else {
                emit(.text(Character(scalar)))
            }

        case .escape:
            if scalar == "[" {
                state = .csiEntry
                resetCSIBuffers()
            } else if scalar == "]" {
                state = .osc
            } else if scalar == "\u{1B}" {
                // 连续的 ESC，丢弃前一个，以新的 ESC 重新进入 escape
                state = .escape
            } else {
                // 不支持的 escape 序列，丢弃 ESC，将当前字节作为文本处理
                state = .ground
                emit(.text(Character(scalar)))
            }

        case .csiEntry:
            if isParamByte(scalar) {
                state = .csiParam
                paramBuffer = String(scalar)
            } else if isIntermediateByte(scalar) {
                state = .csiIntermediate
                intermediateBuffer = String(scalar)
            } else if isFinalByte(scalar) {
                emit(.csi(params: [], intermediates: "", command: Character(scalar)))
                resetCSIBuffers()
                state = .ground
            } else {
                // 非法 CSI 字节，丢弃整个序列
                resetCSIBuffers()
                state = .ground
            }

        case .csiParam:
            if isParamByte(scalar) {
                paramBuffer.append(Character(scalar))
            } else if isIntermediateByte(scalar) {
                state = .csiIntermediate
                intermediateBuffer = String(scalar)
            } else if isFinalByte(scalar) {
                let params = parseCSIParameters(paramBuffer)
                emit(.csi(params: params, intermediates: intermediateBuffer, command: Character(scalar)))
                resetCSIBuffers()
                state = .ground
            } else {
                // 非法 final byte，丢弃整个 CSI
                resetCSIBuffers()
                state = .ground
            }

        case .csiIntermediate:
            if isIntermediateByte(scalar) {
                intermediateBuffer.append(Character(scalar))
            } else if isFinalByte(scalar) {
                let params = parseCSIParameters(paramBuffer)
                emit(.csi(params: params, intermediates: intermediateBuffer, command: Character(scalar)))
                resetCSIBuffers()
                state = .ground
            } else {
                // intermediate 之后只能继续 intermediate 或 final，否则丢弃
                resetCSIBuffers()
                state = .ground
            }

        case .osc:
            if scalar == "\u{07}" {
                // BEL terminator.
                state = .ground
            } else if scalar == "\u{1B}" {
                state = .oscEscape
            }
            // 其余负载字节全部吞掉，不发事件。

        case .oscEscape:
            if scalar == "\\" {
                // ST (ESC \) terminator.
                state = .ground
            } else if scalar == "\u{1B}" {
                state = .oscEscape
            } else {
                // 不是 ST：ESC 视为负载的一部分，继续吞 OSC。
                state = .osc
            }
        }
    }

    // MARK: - Private

    private func isParamByte(_ scalar: Unicode.Scalar) -> Bool {
        (scalar >= "0" && scalar <= "9")
            || scalar == ";" || scalar == ":"
            || (scalar >= "<" && scalar <= "?")
    }

    private func isIntermediateByte(_ scalar: Unicode.Scalar) -> Bool {
        scalar >= " " && scalar <= "/"
    }

    private func isFinalByte(_ scalar: Unicode.Scalar) -> Bool {
        scalar >= "@" && scalar <= "~"
    }

    private mutating func resetCSIBuffers() {
        paramBuffer = ""
        intermediateBuffer = ""
    }
}

/// 解析 CSI 参数段为参数列表。`ANSIParser` 与 `ByteStreamBuffer` 共用此函数，
/// 从结构上保证两端分隔符规则一致。
///
/// 规则：`;` 分隔参数，`:` 分隔子参数（拍平进同一列表）；空参数按 ECMA-48
/// 惯例记为 0（0 = 使用该参数的默认值），由消费方按命令映射具体默认值；
/// 非数字参数段（如 DEC 私有前缀 `?`）丢弃。
func parseCSIParameters(_ string: String) -> [Int] {
    guard !string.isEmpty else { return [] }
    return string
        .split(omittingEmptySubsequences: false) { $0 == ";" || $0 == ":" }
        .compactMap { $0.isEmpty ? 0 : Int($0) }
}
