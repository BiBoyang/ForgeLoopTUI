# AppKit Hybrid Bridge (P0 — Reusable)

Date: 2026-05-11  
Scope: `ForgeLoopTUI/Bridge/AppKit` — minimal bridge proving one state model drives both TUI and AppKit projections.

---

## 1) Design Motivation

ForgeLoopTUI already has a mature terminal rendering pipeline (`ScreenLayoutRenderer` → `ComposedFrame` → `TUI.render`). M6 asks:

> Can the *same* source state also feed an AppKit panel without forking the state model or duplicating business logic?

The answer is **yes**, via a thin projection layer:

- **One source**: `HybridRenderState` (generic, no terminal/AppKit assumptions).
- **Two read-only projections**:
  1. `TerminalRenderState` → existing `ScreenLayoutRenderer` → `ComposedFrame`.
  2. `AppKitPanelState` → data model for an AppKit consumer to observe and render.

No dual-write. No AppKit semantics leaked into Components. No TUI rewrite.

---

## 2) State Model

### `HybridRenderState` (source of truth)

```swift
public struct HybridRenderState: Sendable, Equatable {
    public var headerLines: [String]
    public var transcriptLines: [String]
    public var queueLines: [String]
    public var statusLines: [String]
    public var inputLines: [String]
    public var pinnedTranscriptRange: Range<Int>?
    public var panelMeta: PanelMeta?
}
```

- All fields are generic UI content lines.
- `panelMeta` is optional metadata for the AppKit side; terminal-only consumers can ignore it.
- `pinnedTranscriptRange` is forwarded unchanged to `ScreenLayoutRenderer`.

### `PanelMeta` (AppKit metadata)

```swift
public struct PanelMeta: Sendable, Equatable {
    public var title: String
    public var summary: String
    public var statusBadge: String
    public var isActive: Bool
}
```

- Pure data. No `NSView`, no Cocoa layout.
- A real AppKit panel would observe `AppKitPanelState.meta` and update its chrome.

### `TerminalRenderState` (terminal projection)

```swift
public struct TerminalRenderState: Sendable, Equatable {
    public var layout: ScreenLayout
    public var config: ScreenLayoutConfig
    public var cursorOffset: Int?
}
```

- Thin wrapper so the bridge speaks its own vocabulary while reusing the existing renderer.

### `AppKitPanelState` (AppKit projection)

```swift
public struct AppKitPanelState: Sendable, Equatable {
    public var transcriptLines: [String]
    public var inputLines: [String]
    public var statusLines: [String]
    public var queueLines: [String]
    public var meta: PanelMeta
    public var inputFocused: Bool
}
```

- Mirrors the logical regions of `HybridRenderState` in a shape convenient for native UI.
- `inputFocused` is derived from `inputLines.isEmpty` (can be extended later).

---

## 3) Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    HybridRenderState                         │
│  (single source of truth, read-only for projections)         │
└──────────────────┬──────────────────────────────────────────┘
                   │
      ┌────────────┴────────────┐
      │                         │
      ▼                         ▼
┌──────────────┐      ┌─────────────────┐
│  Terminal    │      │  AppKitPanel    │
│  Projection  │      │  Projection     │
└──────┬───────┘      └────────┬────────┘
       │                       │
       ▼                       ▼
┌──────────────┐      ┌─────────────────┐
│ ScreenLayout │      │  AppKit consumer│
│   Renderer   │      │  (observes data)│
└──────┬───────┘      └─────────────────┘
       │
       ▼
┌──────────────┐
│ ComposedFrame│
└──────────────┘
```

Key invariants:

1. **Single source** — `HybridRenderState` is the only mutable state.
2. **Read-only projections** — `HybridRenderAdapter` never writes back.
3. **Zero AppKit in library** — no `import AppKit`, no `NSView` subclasses in `ForgeLoopTUI`.
4. **Zero TUI rewrite** — `ScreenLayoutRenderer` is used exactly as before.

---

## 4) Adapter API

`HybridRenderAdapter` is a pure `Sendable` struct with no retained state:

```swift
public struct HybridRenderAdapter: Sendable {
    public init()

    /// Terminal projection → ComposedFrame
    public func renderTerminal(
        state: HybridRenderState,
        config: ScreenLayoutConfig,
        cursorOffset: Int?
    ) -> ComposedFrame

    /// AppKit projection → data model
    public func appKitProjection(of state: HybridRenderState) -> AppKitPanelState

    /// Both at once (primary demo entry point)
    public func renderBoth(
        state: HybridRenderState,
        config: ScreenLayoutConfig,
        cursorOffset: Int?
    ) -> (terminal: ComposedFrame, appKit: AppKitPanelState)
}
```

---

## 5) Implemented Range

| Item | Status |
|---|---|
| `HybridRenderState` source model | ✅ |
| `PanelMeta` metadata struct | ✅ |
| `TerminalRenderState` projection | ✅ |
| `AppKitPanelState` projection | ✅ |
| `HybridRenderAdapter` dual renderer | ✅ |
| Bridge tests (13 tests, 6 coverage areas) | ✅ |
| Terminal path regression: `ScreenLayoutRendererTests` | ✅ |
| Integration path regression: `ScreenLayoutIntegrationTests` | ✅ |
| Documentation (this file + plan updates) | ✅ |
| `AppKitEventAdapter` (NSEvent → KeyEvent) | ✅ |
| `HybridObservableState` (`@Observable` wrapper, `@MainActor`) | ✅ |
| `PanelMetadataProviding` protocol + bridge to `PanelMeta` | ✅ |
| `PanelMeta` rich fields (subtitle, accessoryBadge) | ✅ |
| Adapter degradation paths | ✅ |
| Input adapter tests (18 contract tests) | ✅ |
| Observable state tests (14 lifecycle tests) | ✅ |

---

## 6) Unimplemented / Out of Scope

| Item | Reason |
|---|---|
| Real `NSView` subclass | P0 is data-only bridge; AppKit views live in app target |
| Animation / transition policies | Product UI concern, not bridge concern |
| Accessibility labels / NSAccessibility | Product UI concern |

---

## 7) Next Steps (P1 / M7)

P0 已完成双向桥接闭环（NSEvent→KeyEvent + @MainActor Observable state + 降级路径 + PanelMetadataProviding→PanelMeta 桥接入口）。P0 不引入新的公开错误 API。

后续方向：
1. **真实 AppKit 应用验证** — 在 `ForgeLoop`（非 `ForgeLoopTUI`）中创建最小 macOS 应用，将 `AppKitPanelState` 渲染到 `NSTextView` + `NSStackView`。
2. **Accessibility** — 为 AppKit 面板补充 `NSAccessibility` 标签与焦点管理。
3. **动画策略** — 产品 UI 层面的过渡与刷新策略。
4. **发布工程** — 为 `ForgeLoopTUI` 打 tag，发布 DocC API 文档，完善集成指南。

---

## 8) Files

- `Sources/ForgeLoopTUI/Bridge/AppKit/HybridRenderState.swift`
- `Sources/ForgeLoopTUI/Bridge/AppKit/HybridRenderAdapter.swift`
- `Sources/ForgeLoopTUI/Bridge/AppKit/AppKitEventAdapter.swift`
- `Sources/ForgeLoopTUI/Bridge/AppKit/HybridObservableState.swift`

- `Tests/ForgeLoopTUITests/Bridge/HybridRenderAdapterTests.swift`
- `Tests/ForgeLoopTUITests/Bridge/AppKitEventAdapterTests.swift`
- `Tests/ForgeLoopTUITests/Bridge/HybridObservableStateTests.swift`
