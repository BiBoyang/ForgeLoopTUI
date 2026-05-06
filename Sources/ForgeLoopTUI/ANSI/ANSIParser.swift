/// ANSI 字节流状态机：将输入文本拆分为普通文本事件与 CSI 控制序列事件。
///
/// 设计目标：
/// - 支持跨 `write()` 调用的分片 CSI 序列拼接。
/// - 最小化：仅识别文本与 CSI，不引入样式语义。
/// - 可被 `VirtualTerminal` 等消费者复用。
public struct ANSIParser: Sendable {
    public enum Event: Sendable {
        /// 一个可见（或控制）字符。
        case text(Character)
        /// 一条已完整解析的 CSI 序列。
        ///
        /// `intermediates` 为中间字节（0x20–0x2F）的拼接字符串，绝大多数 CSI 序列为空。
        case csi(params: [Int], intermediates: String, command: Character)
    }

    private enum State: Sendable {
        case ground
        case escape
        case csiEntry
        case csiParam
        case csiIntermediate
    }

    private var state: State = .ground
    private var paramBuffer: String = ""
    private var intermediateBuffer: String = ""

    public init() {}

    /// 喂入单个 Unicode scalar，通过 `emit` 回调输出事件。
    ///
    /// 若当前 scalar 属于未完成的 CSI 序列，不会触发任何事件，状态被保留
    /// 以供下一次 `feed` 调用继续拼接。
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
                let params = parseParams(paramBuffer)
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
                let params = parseParams(paramBuffer)
                emit(.csi(params: params, intermediates: intermediateBuffer, command: Character(scalar)))
                resetCSIBuffers()
                state = .ground
            } else {
                // intermediate 之后只能继续 intermediate 或 final，否则丢弃
                resetCSIBuffers()
                state = .ground
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

    private func parseParams(_ string: String) -> [Int] {
        string.split(whereSeparator: { $0 == ";" || $0 == ":" }).compactMap { Int($0) }
    }

    private mutating func resetCSIBuffers() {
        paramBuffer = ""
        intermediateBuffer = ""
    }
}
