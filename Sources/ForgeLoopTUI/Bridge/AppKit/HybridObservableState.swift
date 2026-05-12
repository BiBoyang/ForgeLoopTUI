import Foundation
import Observation

/// 可观察的 HybridRenderState 包装器。
///
/// 使用 macOS 14+ `@Observable` 宏提供响应式状态追踪。
/// AppKit/SwiftUI 视图可通过标准的观察模式自动响应状态变化。
///
/// ## 使用方式（AppKit）
/// ```swift
/// let state = HybridObservableState()
/// withObservationTracking {
///     _ = state.transcriptLines  // 触发追踪
/// } onChange: {
///     // 状态变化时更新 UI
/// }
/// ```
///
/// ## 线程语义
/// - 本类型标记为 `@MainActor`，应在主线程创建与修改。
/// - 作为 UI 状态容器，不保证跨 actor 传递安全；不声明普通 `Sendable`。
@available(macOS 14, *)
@Observable
@MainActor
public final class HybridObservableState {

    /// 底层 HybridRenderState
    public private(set) var state: HybridRenderState

    /// 便捷计算属性：用于 Observation 追踪
    public var transcriptLines: [String] { state.transcriptLines }
    public var inputLines: [String] { state.inputLines }
    public var statusLines: [String] { state.statusLines }
    public var queueLines: [String] { state.queueLines }
    public var headerLines: [String] { state.headerLines }
    public var panelMeta: PanelMeta { state.panelMeta ?? PanelMeta() }
    public var isInputFocused: Bool { !state.inputLines.isEmpty }

    public init(initialState: HybridRenderState = HybridRenderState()) {
        self.state = initialState
    }

    /// 整体替换状态（触发所有观察者）
    public func update(_ newState: HybridRenderState) {
        state = newState
    }

    /// 按字段更新（细粒度，仅触发变化字段的观察者）
    public func updateTranscript(_ lines: [String]) { state.transcriptLines = lines }
    public func updateInput(_ lines: [String]) { state.inputLines = lines }
    public func updateStatus(_ lines: [String]) { state.statusLines = lines }
    public func updateQueue(_ lines: [String]) { state.queueLines = lines }
    public func updateHeader(_ lines: [String]) { state.headerLines = lines }
    public func updateMeta(_ meta: PanelMeta) { state.panelMeta = meta }
    public func updatePinnedRange(_ range: Range<Int>?) { state.pinnedTranscriptRange = range }
}
