# ForgeLoopTUI Source Structure and Reuse Refactor Plan

Date: 2026-05-07
Scope: file layout, module boundaries, and code reuse strategy

## 1) Why This Refactor Is Needed

Current source files are mostly flat under one directory. This creates:

1. unclear ownership boundaries
2. difficult navigation for new contributors
3. higher coupling between runtime, parsing, input, and rendering concerns
4. reduced reuse when building additional apps on top of the framework

## 2) Refactor Goals

1. establish clear directories that map to runtime responsibilities
2. maximize reuse of core logic between terminal mode and future AppKit bridge
3. isolate volatile code (input/ansi runtime details) from stable code (core models)
4. keep migration incremental to avoid high-risk rewrites

## 3) Proposed Source Tree

Target tree under `Sources/ForgeLoopTUI`:

```text
Sources/ForgeLoopTUI/
  Core/
    Frame.swift
    Cell.swift
    Viewport.swift
    DiffPlan.swift
    LayoutBudget.swift
  ANSI/
    ANSIParser.swift
    ANSIEncoder.swift
    ANSIStyle.swift
    ColorProfile.swift
    DisplayWidth.swift
  Terminal/
    Terminal.swift
    StdoutTerminal.swift
    VirtualTerminal.swift
    TerminalCapabilities.swift
  Input/
    RawTTY.swift
    StdinBuffer.swift
    KeyEvent.swift
    KeyParser.swift
    KeyMapper.swift
  Runtime/
    TUIRuntime.swift
    RenderLoop.swift
    RenderStrategy.swift
    ResizeCoordinator.swift
  Transcript/
    CoreRenderEvents.swift
    RenderEvents.swift
    TranscriptRenderer.swift
    StreamingTranscriptAppendState.swift
  Markdown/
    MarkdownEngine.swift
    LogicalLines.swift
  Components/
    Component.swift
    Container.swift
    TextComponent.swift
    InputComponent.swift
    ModalHost.swift
    ListPicker.swift
  Style/
    Style.swift
  Bridge/
    AppKit/
      TUIView.swift
      AppKitInputAdapter.swift
  Compat/
    LegacyRenderAdapter.swift
```

## 4) File Migration Mapping

Recommended mapping from current files:

1. `TUI.swift` -> split into `Runtime/TUIRuntime.swift`, `Runtime/RenderStrategy.swift`, `Terminal/StdoutTerminal.swift`
2. `TerminalMetrics.swift` -> `ANSI/DisplayWidth.swift`
3. `RenderLoop.swift` -> `Runtime/RenderLoop.swift`
4. `MarkdownEngine.swift` -> `Markdown/MarkdownEngine.swift`
5. `CoreRenderEvents.swift` + `RenderEvents.swift` -> `Transcript/`
6. `TranscriptRenderer.swift` -> `Transcript/TranscriptRenderer.swift`
7. `StreamingTranscriptAppendState.swift` -> `Transcript/`
8. `TextInput.swift` -> `Components/InputComponent.swift` + `Input/KeyEvent.swift` integration
9. `Modal.swift` -> `Components/ModalHost.swift` + `Components/ListPicker.swift`
10. `Style.swift` -> `Style/Style.swift`
11. `LogicalLines.swift` -> `Markdown/LogicalLines.swift`

## 5) Test Tree Realignment

Target tree under `Tests/ForgeLoopTUITests`:

```text
Tests/ForgeLoopTUITests/
  Core/
  ANSI/
  Terminal/
  Input/
  Runtime/
  Transcript/
  Markdown/
  Components/
  Integration/
  Performance/
```

Guidelines:

1. tests should mirror source directory ownership
2. behavior tests for rendering should prefer `VirtualTerminal`
3. integration tests should cover streaming + input + resize combined

## 6) Reuse Strategy

1. keep `Core`, `ANSI`, and `Input` free from app-specific assumptions
2. keep `Runtime` generic and avoid coupling with agent event vocabulary
3. keep transcript adapters in `Compat` or app-side integration layers
4. app projects should compose the framework, not fork runtime internals

## 7) Migration Phases

## Phase A - Low-risk moves

1. create directory skeleton
2. move files without semantic changes
3. keep type names and public signatures unchanged

Exit criteria:

1. build and test unchanged from behavior perspective

## Phase B - Internal extraction

1. extract terminal abstraction and input pipeline types
2. add compatibility wrappers where names change
3. keep external API source-compatible where practical

Exit criteria:

1. existing examples and tests pass without app-side rewrites

## Phase C - Behavior upgrades

1. add virtual terminal, parser hardening, and commit/live semantics
2. upgrade components and layout composition
3. add AppKit bridge sample

Exit criteria:

1. roadmap milestones M1-M6 have passing tests and updated docs

## 8) Coding Conventions for This Refactor

1. one primary responsibility per file
2. avoid cross-directory cyclic dependencies
3. prefer internal access unless API is intentionally public
4. expose extension points through protocols before adding concrete coupling
5. add focused comments only where behavior is non-obvious

## 9) Pull Request Slicing Rules

1. no mixed PR that combines directory moves and behavior changes
2. first PR in each phase should be structure-only
3. parser/input/runtime behavior changes must include replay tests
4. every refactor PR must update `README` or docs when API/discovery changes

## 10) Immediate Next Step

Execute Phase A first and keep it purely structural. Start behavior changes only after tests are green on the new tree.

## 11) Dataflow Companion

This plan defines file ownership and migration shape. For cross-module collaboration and dependency direction (including ASCII dataflow maps), see:

- `docs/module-dataflow-and-dependency-map.md`
