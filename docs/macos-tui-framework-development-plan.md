# ForgeLoopTUI macOS Framework Development Plan

Date: 2026-05-07
Scope: `ForgeLoopTUI` as a reusable, macOS-first TUI framework

## 1) Objective

Build `ForgeLoopTUI` into a production-grade TUI framework that can:

1. power complex terminal applications with stable input and rendering
2. provide reusable APIs across multiple apps
3. match key KWWK TUI capabilities in reliability and developer ergonomics
4. create a clear differentiator in the Swift ecosystem through AppKit + TUI hybrid rendering

## 2) Scope and Non-Goals

In scope:

1. terminal runtime and rendering semantics
2. ANSI parsing, encoding, color profiles, and width correctness
3. raw stdin input pipeline and key mapping
4. component protocol and layout composition
5. virtual terminal test infrastructure
6. performance baselines and regression gates
7. AppKit bridge and hybrid demo app

Out of scope for this plan:

1. AI provider expansion (OAuth, more model providers)
2. agent/tool feature expansion unrelated to TUI runtime
3. cross-platform parity (Linux/Windows) in v1

## 3) Acceptance Criteria

A milestone is accepted only if all criteria pass:

1. `swift test` is green for unit, behavior, and integration suites
2. virtual terminal tests cover core redraw, cursor, and resize paths
3. no terminal state leaks after exit, cancel, crash simulation, or forced stop
4. input processing is correct for partial CSI chunks and UTF-8 boundaries
5. live streaming stays stable under long outputs and resize pressure
6. benchmark regressions are within defined thresholds

## 4) Target Architecture

Organize `ForgeLoopTUI` into clear runtime boundaries:

1. `Core`
- frame model, viewport, cell model, diff plan, and layout budget

2. `ANSI`
- stream parser state machine
- SGR and CSI encoder
- color profile and capability downgrade
- escape-aware width and truncation helpers

3. `Terminal`
- `Terminal` protocol
- `StdoutTerminal` for real tty
- `VirtualTerminal` for deterministic tests

4. `Input`
- raw tty lifecycle
- stdin buffering and sequence assembly
- key parsing and normalized `KeyEvent` model

5. `Components`
- component protocol and common primitives (`Text`, `Input`, `Container`, `ModalHost`)

6. `Runtime`
- retained live zone rendering
- commit/live transcript semantics
- render scheduling and resize handling

7. `Bridge/AppKit`
- `NSView` adapter for TUI frame rendering
- AppKit event adapter to shared `KeyEvent`

## 4.1) Dataflow and Dependency Reference

For a concrete end-to-end module collaboration view (including ASCII diagrams for:

1. render event to screen output path
2. ANSI handling stages in the render pipeline
3. dependency direction rules

see:

- `docs/module-dataflow-and-dependency-map.md`

## 5) Milestone Plan

## M0 - Specs and Baseline (2-3 days)

Deliverables:

1. freeze API direction and migration policy
2. define benchmark scenarios and output format
3. document explicit non-goals for v1

Definition of Done:

1. architecture doc is merged
2. benchmark script runs locally and outputs reproducible metrics
3. public API change policy is written and versioned

## M1 - Terminal Abstraction and VirtualTerminal (4-5 days)

> Status: completed (merged)
>
> Completed items:
> - `Terminal` protocol with `write(_:)` and `isTTY`
> - `StdoutTerminal` as default real-tty implementation
> - `VirtualTerminal` minimal emulator: grid, cursor, clear, scroll, resize, illegal-size guards
> - CSI parser supports `;`-delimited params and ignores unsupported finals (e.g. SGR `m`)
> - TUI output wiring switched to `Terminal` with backward-compatible `FrameWriter` shim
> - Screen-state assertions via `VirtualTerminal` for legacy clear/home, inline first/second frame, cursor offset, append frame, and reset retained frame
>
> Deferred to later milestones:
> - Full ANSI parser state machine and SGR style tracking → M2
> - Raw TTY / stdin input pipeline → M3
> - Commit/live rendering semantics upgrade → M4
> - AppKit bridge → M6

Deliverables:

1. introduce `Terminal` protocol to remove direct stdout coupling ✅
2. implement `StdoutTerminal` as the default protocol-backed output ✅
3. implement `VirtualTerminal` grid, cursor, clear, scroll, and resize behavior ✅
4. port existing render tests to virtual terminal assertions ✅

Definition of Done:

1. render behavior tests run without a real tty ✅
2. cursor and row-level assertions are deterministic ✅
3. no behavior regressions in current public API tests ✅

## M2 - ANSI Subsystem Hardening (5-7 days)

> Status: completed (merged)
>
> Completed items:
> - `ANSIParser` state machine with 5 states (ground/escape/csiEntry/csiParam/csiIntermediate), chunk-safe across `write()` calls
> - Full CSI byte categories: param (0x30-0x3F), intermediate (0x20-0x2F), final (0x40-0x7E)
> - `VirtualTerminal` cursor positioning (`ESC[row;colH`) and `Cell` model with `SGRState` tracking
> - SGR support: reset, bold, dim, standard/bright fg/bg (30-37, 40-47, 90-97, 100-107)
> - 256-color (`indexed`) and 24-bit TrueColor (`rgb`) with safe incomplete-param handling
> - `TerminalCapability` enum (plain/ansi16/ansi256/truecolor) wired through `Terminal` protocol
> - Style degradation chain: rgb → indexed → standard/bright → plain, capability-driven rendering
> - End-to-end tests: parser (18), style tracking (16), capability degradation (12), render chain (10)
>
> Deferred:
> - unified width/truncation APIs across runtime paths → M4/M5

Deliverables:

1. state-machine ANSI parser with chunk-safe streaming ✅
2. SGR support for style reset, fg/bg colors, and attributes ✅
3. color profile support: plain, 16-color, 256-color, truecolor ✅
4. unified width/truncation APIs across runtime paths ⏸️

Definition of Done:

1. mixed ANSI + CJK + emoji width tests are stable ✅
2. parser passes partial-sequence replay tests ✅
3. style downgrade policy works in capability-restricted terminals ✅

## M3 - RawStdin and Input Pipeline (6-8 days)

> Status: completed
>
> Completed items:
> - `RawTTY` raw tty enter/restore lifecycle with robust cleanup (double-enter guard, RAII `withRawTTY`, deinit restore)
> - `ByteStreamBuffer` stdin buffer for fragmented escape sequences and UTF-8 reassembly; illegal-byte blocking bug fixed
> - `KeyEvent` / `KeyParser` normalized key model (character/arrow/home/end/F1-F12/Ctrl/Alt/Shift/modifier) with CSI + SS3 mapping
> - `InputPipeline` bracketed paste (`ESC[200~` / `ESC[201~`) and ESC flush timer (50ms default via injectable `InputClock`)
>   - **Integration note**: `InputPipeline.tick()` must be scheduled by the upper event loop (e.g. `DispatchSourceTimer` or `select` + timerfd) to resolve standalone ESC vs Alt+char ambiguity.
> - Tests: RawTTY (6), ByteStreamBuffer (18), KeyParser (19), InputPipeline (22)

Definition of Done:

1. input replay tests pass for fragmented sequences ✅
2. paste, cancellation, and UTF-8 boundaries are correct ✅
3. terminal settings are restored after forced interruption ✅

## M4 - Render Semantics Upgrade (5-7 days)

Deliverables:

1. explicit commit/live rendering model
2. live budget and overflow settlement policy
3. tool-slot ordering semantics for out-of-order completions
4. resize-safe frame anchoring and cursor positioning

Definition of Done:

1. long streaming transcripts do not flicker or reorder
2. resize stress tests keep cursor and content alignment correct
3. commit region and live region behavior is deterministic

## M5 - Componentization and Layout System (6-8 days)

Deliverables:

1. component protocol and reusable primitives
2. container and layout budget orchestration
3. migration path from monolithic controller usage
4. adapters for current `TranscriptRenderer` and `TextInput` integration

Definition of Done:

1. a non-trivial UI can be composed without modifying runtime internals
2. app-side integration code shrinks and becomes structurally clear
3. public API remains source-compatible or has a documented migration path

## M6 - AppKit Hybrid Rendering Demo (5-7 days)

Deliverables:

1. sample macOS app using shared state model
2. left panel: TUI transcript, right panel: native AppKit inspector
3. shared event flow between TUI state and native panel actions

Definition of Done:

1. demo proves one state model driving both render paths
2. AppKit and terminal modes share component logic where expected
3. demo is stable enough for repeatable local showcase

## M7 - Stabilization and Release Prep (3-5 days)

Deliverables:

1. performance regression gates and baseline snapshots
2. API docs and migration notes
3. release checklist and version/tag plan

Definition of Done:

1. benchmark thresholds are documented and enforced
2. docs include setup, extension points, and usage samples
3. release can be cut without manual terminal-workaround steps

## 6) Test Strategy

Required test layers:

1. unit tests for parser, width, truncation, key mapping
2. behavior tests via virtual terminal frame assertions
3. replay tests for stdin chunks and resize event sequences
4. integration tests for transcript + input + runtime interaction
5. performance tests for frame latency, input latency, and throughput

## 7) Performance Gates

Suggested thresholds for local CI baseline:

1. medium-load frame time p95 < 8ms
2. key-to-echo latency p95 < 30ms
3. 10k-line streaming without unbounded memory growth
4. resize storm handling without frame corruption

## 8) Execution Rules During Development

1. prioritize infrastructure before feature breadth
2. no large rewrites without compatibility shims
3. each milestone ends with tests + benchmark + docs update
4. no merge of runtime changes without at least one replay test

## 9) Immediate Next Step

Start with M0 and M1 first. Do not start AppKit bridge before virtual terminal and input reliability are in place.
