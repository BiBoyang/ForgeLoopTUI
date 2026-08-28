# Changelog

All notable changes to this project will be documented in this file.

Format and section names follow `docs/semver-and-api-stability.md` (§7).

## [Unreleased]

### Deprecated
- The declarative component tree is deprecated as an unverified design with no known production consumers and will be removed in 2.0: `Component`, `AnyComponent`, `VStack`, `ComponentBuilder`, `FrameComposer`, `LayoutBudget` (+ `LiveOverflowPolicy`), `ModalRenderer`, and the `TranscriptComponent` / `TextInputComponent` / `ListPickerComponent` wrappers. Render via `TUI.render(committed:live:…)` or the `TranscriptRenderer`/`CoreRenderEvent` event model instead. The underlying value types (`ComposedFrame`, `ScreenLayout`, `TextInputState`, `ListPickerState`, …) are unaffected.

### Removed
- Dropped the nominal Linux support: the eight `#if canImport(Glibc)` branches were removed (the code targets Darwin directly — `StdoutTerminal` hardcodes `Darwin.write`, the bridge unconditionally imports AppKit — so Linux never actually built). The README now states the supported platform matrix explicitly: macOS 14+ only.

### Added
- `visibleWidth(_:)` and `ansiStripped(_:)` are now public: ANSI-aware terminal-cell width measurement (per grapheme cluster; wide CJK/emoji 2 cells, combining marks 0) and CSI escape stripping. They are the implementations already used by `MultiLineInputState`, `physicalRows(for:width:)`, and `TUI` cursor placement, and replace hand-written duplicates in consumers (e.g. ForgeLoop's rendering helpers).
- `StdoutTerminal.onWriteFailure` and `RawTTY.onRestoreFailure`: optional hooks reporting the failing `errno` for stdout writes and termios restores — the reporting channel for the documented "Terminal.write does not throw" limitation (see `docs/known-limitations.md`).

### Fixed
- `StdoutTerminal.isTTY` and `StdoutTerminal.capability` no longer hardcode `true`/`.truecolor`; they probe the real environment (`isatty` + `COLORTERM`/`TERM`, `TERM=dumb` → `.plain`).
- Removed force unwraps / provably-trapping constructions in `KeyParser` (Ctrl-letter and ASCII scalar construction now use the non-failable `Unicode.Scalar(UInt8)` initializer), `AppKitEventAdapter`, and `FrameComposer`'s overflow-marker assembly (now `if let`).
- `TUI`'s `@unchecked Sendable` is now honored: a render pass used to swap state under the lock but assemble output and call `terminal.write` outside it, so concurrent renders could interleave/garble frames. Each pass (state swap + assembly + write) is now fully serialized by a dedicated render lock, and the previously unsynchronized `diagnosticsHandler` property is lock-protected. The handler is now invoked while the render lock is held — it must not call back into `TUI` render methods (documented on the property). Verified with a new concurrency suite, clean under ThreadSanitizer.
- `TranscriptRenderer` block events are now single-active-block with id matching: previously the block `id` was silently dropped and a second `blockStart` clobbered the open block's streaming state. A `blockStart` arriving while another block is open implicitly finalizes that block (keeping its content), and `blockUpdate`/`blockEnd`/`blockCancel` with a mismatched `id` while another block is open are ignored; the loose no-active-block behavior is preserved for compatibility. Verified against the only known consumer (ForgeLoop), which never runs concurrent blocks.
- CSI parameter parsing (`ANSIParser` and `ByteStreamBuffer`) now preserves empty parameters as 0 (the ECMA-48 "use default" marker) instead of dropping them — `ESC[;5H` parses as `[0, 5]`, so the omitted first parameter no longer shifts later values into the wrong slot. Both parsers also share one implementation now, so `:` subparameters are flattened identically on both sides (previously `ByteStreamBuffer` dropped colon-containing segments entirely).
- `StreamingTranscriptAppendState.consume(transcript:activeRange:)` clamps both ends of `activeRange` to the transcript bounds; a stale range past the end of a shrunk transcript no longer crashes on an out-of-bounds subscript.
- Display width is now counted per grapheme cluster instead of per Unicode scalar: ZWJ emoji sequences (👨‍👩‍👧‍👦), skin-tone modifiers (👍🏽), VS16 emoji presentation (❤️), and regional-indicator flags (🇨🇳) count as 2 cells, combining marks (Mn/Me) as 0. Fixes cursor drift in `physicalRows(for:width:)`, `MultiLineInputState` rendering/navigation, and TUI cursor placement; `MultiLineInputState`'s duplicated width logic was removed in favor of the shared implementation. Covered by new `DisplayWidthTests`.

## [1.2.1] — 2026-08-13

### Fixed
- TranscriptRenderer: thinking-block and streaming in-place replacements that change line counts now shift tracked indices (pendingTools, notificationLines, streamingRange, completedRange, thinkingRange) by the line delta; `shiftIndices` compares range lowerBounds so adjacent ranges are not widened incorrectly. Covered by new `TranscriptRendererIndexShiftTests`.
- MarkdownEngine: `stableAdvance` now retreats when the stable-prefix candidate ends inside an unclosed code fence (`retreatToAvoidSplittingUnclosedCodeFence`), preventing the live tail from being re-parsed with `inCodeFence = false` and misrendering the closing fence as a new opening. Fence retreat runs before table retreats and reuses `isCodeFenceDelimiter` semantics.

## [1.2.0] — 2026-06-16

### Added
- VirtualTerminal CHA (ESC[G]) support for full .marker cursor testing
- Markdown strikethrough (~~text~~) via SGR 9
- Markdown task list (- [ ] / - [x]) with ☐/☑

### Changed
- TextInputTests expanded with CJK, wide-char scrolling, and viewport edge coverage

### Deprecated
- AppKitBridgeError (unused, removed in 2.0.0)

## [1.1.0] — 2026-06-13

### Added
- `Modifiers.command` bit and AppKit event-adapter mapping.
- `TranscriptRenderOptions` for configurable summary and notification limits.
- `CoreRenderEvent.blockCancel` for mid-stream cancellation.
- `CoreRenderEvent.thinking` for reasoning/thinking content.
- Inline Markdown rendering: code spans, bold, italic, and links.
- `TUI.diagnosticsHandler` for render decision observability.
- `CONTRIBUTING.md`, README table of contents.

### Fixed
- `TUI.invalidate()` no longer empty — recalculates physical row caches inside lock.
- `VirtualTerminal` supports CSI `L`/`M` (insert/delete lines) for fast-path test parity.
- `TranscriptRenderOptions` clamps negative values to avoid crashes.
- `LiveBudgetPlanner` adds explicit invariant assert.

### Changed
- Extracted shared `scalarIsWide()` to eliminate 100-line Unicode range duplication.
- Removed hardcoded API key fallback from DeepSeekChat example.
- Removed internal working docs from public `docs/`.
- `StreamingMarkdownEngine` stable prefix capped at 64 KB to bound memory in long sessions.
- `.gitignore` expanded for Xcode/IDE artifacts.
- `TESTING.md` uses repo-root-relative paths.

## [1.0.0] — 2026-05-23

### Added
- `1.0.0` release line for consumers who need SemVer-stable dependency pinning.

### Changed
- SemVer policy is now explicitly post-1.0 (`docs/semver-and-api-stability.md`), including updated deprecation example removal target (`1.1.0`).
- Version references are aligned to `1.0.0` across release-facing docs (`README.md`, `docs/public-api-surface.md`, `docs/performance-baseline.md`, `docs/migration-guide-for-forgeloopcli.md`).
- Maturity scorecard governance records were completed with line-precise evidence packs for historical over-cap score deltas.

### Deprecated
- None.

### Removed
- None.

### Fixed
- Documentation ambiguity in score update eligibility wording ("同时满足以下至少一项" -> "满足以下任一项").

### Security
- None.

## [0.2.0] — 2026-05-14

### Added
- `TUI.cursorPositioningMode` now exposes `.relative` (default) and `.marker` (physical-row + `CHA`) cursor positioning strategies for different terminal reliability needs.
- `Viewport` and `MultiLineInputState.setViewport(_:)` provide visual-row aware `moveUp` / `moveDown` navigation for wrapped multi-line input.
- AppKit bridge surfaces were expanded with `AppKitEventAdapter`, `HybridObservableState`, and `PanelMetadataProviding` bridge helpers.
- Baseline performance gates were codified for `LiveBudgetPlanner`, `MultiLineInputState`, and `KeyResolver` hot paths.
- `TableRenderPolicy` gains `WideTableStrategy` (`alwaysBox` / `autoReadable`) with configurable readability thresholds (`autoReadableTruncatedCellThreshold`, `autoReadableTrimmedWidthThreshold`). Heavily truncated tables can now degrade back to raw markdown instead of unreadable box-drawing.
- `TableStreamingBehavior` (`monotonic` / `strict`) controls whether incomplete streaming tables are rendered progressively or held as raw markdown until terminated.

### Changed
- API stability governance was tightened with explicit commitments around defaults, error behavior, and concurrency contracts.
- `docs/performance-baseline.md` is now the canonical baseline gate reference for release validation.
- Cross-repo quick validation (`./Scripts/cross-repo-gate.sh --quick`) consolidates build, smoke, and integration checks across `ForgeLoopTUI` and `ForgeLoop`.

### Deprecated
- None.

### Removed
- None.

### Fixed
- `MultiLineInputState` now rejects C0 control characters and `DEL` on `.insert(Character)` while still allowing tab input.
- `.marker` cursor mode avoids emitting cursor-control sequences on non-TTY output paths.

### Security
- None.
