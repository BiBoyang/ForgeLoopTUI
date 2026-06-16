import Foundation

/// AppKit Bridge 层可能产生的错误。
@available(*, deprecated, message: "AppKitBridgeError is unused and will be removed in 2.0.0")
public enum AppKitBridgeError: Error, Sendable, Equatable {
    /// 输入事件无法映射到 KeyEvent（如未知 specialKey、无字符且无 keyCode 匹配）
    case unmappableEvent(description: String)

    /// HybridRenderState 的字段之间存在逻辑冲突
    case inconsistentState(description: String)

    /// 终端尺寸无效（width 或 height 为 0 或负数）
    case invalidTerminalSize(width: Int, height: Int)

    /// AppKit 面板元数据缺失（panelMeta 为 nil 且无默认值可用）
    case missingPanelMetadata
}
