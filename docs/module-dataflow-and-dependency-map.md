# ForgeLoopTUI Module Dataflow and Dependency Map

Date: 2026-05-07
Scope: module collaboration map for TUI render path and ANSI-related stages

## 1) Purpose

This document answers one core architecture question:

"Through which modules does a TUI render event pass, from ANSI handling to final screen output?"

This file focuses on runtime collaboration and dependency direction.

## 2) High-Level Dependency Graph

```text
                       +---------------------+
                       |   Bridge / AppKit   |
                       |  (optional frontend)|
                       +----------+----------+
                                  |
                                  v
+------------+        +-----------+-----------+        +------------------+
| Components | -----> |     Runtime Layer     | -----> |     Terminal     |
| (UI state) |        | (render scheduling,   |        | (Stdout/Virtual) |
+------+-----+        |  frame diff/commit)   |        +---------+--------+
       |              +-----------+-----------+                  |
       |                          |                              v
       |                          v                     +------------------+
       |                +---------+--------+            |  Screen / Grid   |
       |                |      ANSI        |            | (TTY or virtual) |
       |                | parser/encoder   |            +------------------+
       |                +---------+--------+
       |                          |
       v                          v
+------+-----+        +-----------+-----------+
| Transcript | -----> |      Markdown         |
| events/buf |        | (block/table shaping) |
+------------+        +-----------------------+

Shared utility modules used across layers:
- Core (frame/cell/viewport/diff primitives)
- Input (raw tty/stdin/key events; feeds Components/Runtime interaction)
- Style (semantic style to ANSI/plain text mapping)
```

## 3) End-to-End Render Path (Target Architecture)

The target render pipeline (M1-M4) is:

```text
RenderEvent/CoreRenderEvent
  -> Transcript/CoreRenderEvents + Transcript/TranscriptRenderer
  -> Markdown/MarkdownEngine (text shaping, table rendering)
  -> Runtime/TUIRuntime + Runtime/RenderLoop + Runtime/RenderStrategy
  -> Core primitives (frame/cell/viewport + diff planning)
  -> ANSI subsystem
       - ANSI parser: normalize existing escape-rich chunks when needed
       - ANSI encoder: emit final CSI/SGR stream
       - Color profile downgrade (plain/16/256/truecolor)
  -> Terminal abstraction
       - Terminal/StdoutTerminal (real tty)
       - Terminal/VirtualTerminal (deterministic tests)
  -> terminal screen buffer (or virtual grid assertions)
```

Short version:

```text
Event -> Transcript -> Markdown -> Runtime -> Core/Diff -> ANSI -> Terminal -> Screen
```

## 4) "From ANSI Parsing to Screen Output" Concrete Path

When render content contains ANSI escapes or capability-sensitive styling:

```text
1) Runtime receives candidate line/cell content
2) ANSI parser tokenizes/normalizes escape sequences
3) Runtime applies layout and diff on normalized visible model
4) ANSI encoder rebuilds output stream for target terminal capability
5) StdoutTerminal writes bytes to TTY (or VirtualTerminal applies to grid)
6) user sees final frame/cursor state on screen
```

This keeps parsing and emitting responsibilities explicit and testable.

## 5) Dependency Direction Rules

To avoid cycles and keep modules reusable:

1. `Core` must not depend on `Runtime`, `Terminal`, `Transcript`, or app-specific code.
2. `ANSI` may depend on `Core` utilities, but not on `Components` or `Bridge`.
3. `Terminal` must not depend on transcript semantics.
4. `Runtime` may depend on `Core`, `ANSI`, and `Terminal`; avoid business vocabulary.
5. `Transcript` may depend on `Markdown` and `Style`; avoid terminal I/O coupling.
6. `Bridge/AppKit` is outer-layer adapter; it should not pull internals upward.
7. `Compat` adapters can depend inward, but new code should depend on core abstractions first.

Allowed direction (simplified):

```text
Components -> Transcript -> Markdown -> Runtime -> Terminal
                         -> Core    -> ANSI ----^
Input ------------------------------> Runtime/Components
Bridge/AppKit ---------------------> Runtime/Components
```

## 6) Test Ownership by Pipeline Stage

Recommended ownership mapping:

1. `Tests/.../Transcript`: event application, pending tool replacement, streaming range
2. `Tests/.../Markdown`: markdown/table rendering and fallback policy
3. `Tests/.../Runtime`: frame scheduling, redraw semantics, cursor anchoring
4. `Tests/.../Terminal`: virtual terminal cursor/grid/resize assertions (M1+)
5. `Tests/.../Integration`: event -> render -> output path cross-module checks

This preserves a one-way architecture and keeps regressions localizable.
