# Changelog

All notable changes to this project will be documented in this file.

Format and section names follow `docs/semver-and-api-stability.md` (§7).

## [Unreleased]

### Changed
- MinimalAIApp now previews the unstable tail of the in-flight streaming block in the committed region (`TUI.render(committed:live:cursorPlacement:)`), so markdown appears line by line as it streams instead of popping in once settled. Newly stable lines settle into the scrollback through the oracle-pinned sequence — erase the in-place region with an empty anchored render, `appendFrame`, then re-render the remaining preview — and every frame stays anchored end to end (pinned by `CommittedPreviewAnchorTests`). When preview + live exceed the terminal height the library's existing full-redraw fallback applies; long-content soak remains TASK-29 scope.
- `TUI` init no longer assumes `isTTY == true` when the parameter is omitted: unspecified `isTTY` now probes the real environment (`terminal.isTTY` when a terminal is supplied, otherwise the stdout `isatty` probe shared with `StdoutTerminal`). Piped output therefore degrades to plain (non-ANSI) rendering automatically; callers passing an explicit `isTTY` are unaffected. Library tests that relied on the implicit default now state their TTY intent explicitly.

### Deprecated
- The declarative component tree is deprecated as an unverified design with no known production consumers and will be removed in 2.0: `Component`, `AnyComponent`, `VStack`, `ComponentBuilder`, `FrameComposer`, `LayoutBudget` (+ `LiveOverflowPolicy`), `ModalRenderer`, and the `TranscriptComponent` / `TextInputComponent` / `ListPickerComponent` wrappers. Render via `TUI.render(committed:live:…)` or the `TranscriptRenderer`/`CoreRenderEvent` event model instead. The underlying value types (`ComposedFrame`, `ScreenLayout`, `TextInputState`, `ListPickerState`, …) are unaffected.
- `StreamingTranscriptAppendState.consume(transcript:activeRange:)` is deprecated in 1.3.0 and will be removed in 2.0: its drop-last heuristic treats every rendered line of the streaming block except the last as committed, which re-emits already-printed lines whenever the engine re-renders earlier lines mid-stream (see Fixed below). Use `consume(transcript:activeRange:stableLineCount:)` with `TranscriptRenderer.activeStreamingStableLineCount`.

### Removed
- Dropped the nominal Linux support: the eight `#if canImport(Glibc)` branches were removed (the code targets Darwin directly — `StdoutTerminal` hardcodes `Darwin.write`, the bridge unconditionally imports AppKit — so Linux never actually built). The README now states the supported platform matrix explicitly: macOS 14+ only.

### Added
- Kitty keyboard protocol support for distinguishing modifier+Enter from plain Enter. Under the legacy terminal protocol both Shift+Enter and Enter arrive as 0x0D, so consumers (e.g. a multi-line editor that submits on Enter and inserts a newline on Shift+Enter) could not tell them apart. `RawTTY.enter()` now pushes the kitty progressive-enhancement flag `disambiguate escape codes` (`ESC[>1u`) after entering raw mode, and `restore()` pops it (`ESC[<u`) on every exit path (`InputReader.stop()`, `withRawTTY` defer, `deinit`); terminals without kitty support absorb both sequences silently and keep legacy behavior. The writes are best-effort, go to the RawTTY fd itself (guaranteed a TTY by `enter()`), and a failed write never fails raw-mode entry or restore. `KeyParser` decodes the resulting CSI-u sequences (`ESC [ keycode [; modifiers] u`): keycode 13 maps to `.enter` with the modifier field decoded per the kitty spec (field value N means modifier bits N-1: bit0 shift, bit1 alt, bit2 ctrl), so `ESC[13;2u` is Shift+Enter and `ESC[13;5u` is Ctrl+Enter. CSI-u sequences with other keycodes are currently dropped as unknown keys, matching the existing unknown-sequence convention.
- Markdown links are now clickable in OSC 8-capable terminals (iTerm2, kitty, WezTerm, Ghostty, Warp, VS Code; terminals without OSC 8 support absorb the sequences silently). Under the default theme, `[text](url)` link text and bare `http://`/`https://` URLs render as `ESC]8;;…` hyperlinks; bare URLs also gain underline styling, with trailing ASCII/CJK punctuation (`).。，；`) trimmed off the link target. Code spans and fenced code are untouched, and `MarkdownTheme.none` keeps the pre-hyperlink byte stream exactly. Two ANSI-layer enablers: `ansiStripped(_:)`/`visibleWidth(_:)` now strip OSC sequences (BEL- or ST-terminated), so hyperlinked lines measure correctly in all width/layout math, and `ANSIParser` swallows OSC sequences whole so the `VirtualTerminal` oracle matches real-terminal behavior.
- JavaScript fenced code blocks (`` ```javascript ``/`` ```js ``, same info-string matching) are now syntax-highlighted through the same `MarkdownTheme.code` slots and line-level tokenizer protocol as Python: keywords (ECMAScript reserved words plus the `true`/`false`/`null`/`undefined` literals), strings (`'…'`/`"…"` with backslash escapes), template literals (tracked across lines through the explicit continuation), `//` line comments, `/* … */` block comments (tracked across lines), and numbers (`_` separators, floats, exponents, `0x`/`0o`/`0b`, `n` bigint suffix). Segments partition each source line and wrap only in complete SGR sequences, so `MarkdownTheme.none` keeps the pre-highlight byte stream exactly and unrecognized languages render plain. Documented approximations: `${…}` interpolation is not parsed (the whole template literal is one string segment) and regex literals are not recognized (`/` starts a comment only when doubled or starred). The second-language integration cost was one new tokenizer file plus a one-line branch in the fence info-string switch; the engine wiring and theme slots were reused unchanged (TASK-31).
- Python fenced code blocks (`` ```python ``/`` ```py ``, matched on the lowercased first info-string token) are now syntax-highlighted with the `MarkdownTheme.code` slots: a small built-in line-level tokenizer — no third-party dependency — classifies keywords (`keyword.kwlist`; builtins like `print` stay plain), strings (`r`/`b`/`f`/`u` prefixes, backslash escapes, triple-quoted literals tracked across lines through an explicit continuation the fence loop threads line by line), `#` comments, and numbers (`_` separators, floats, exponents, `0x`/`0o`/`0b`, `j` suffix). Highlighted segments partition each source line and are wrapped only in complete SGR sequences, so `MarkdownTheme.none` keeps the pre-highlight byte stream exactly and unrecognized languages (or no info string) render as plain text; the fence border/language-label styling from the block-chrome pass is unaffected. The highlighter holds no hidden state — the continuation is recreated from the fence's first line on every render pass, preserving the stable-prefix commit contract (a fence is never split across render passes). Documented approximations: escapes are honored uniformly inside raw strings, and f-string interpolation is not parsed (the whole literal is one string).
- Common LaTeX now approximates to readable Unicode: inline `$…$`/`$$…$$` spans and `$$` display blocks convert Greek letters (`\alpha`…`\omega`, capitals), the operators `\int \infty \pm \geq \leq \neq \cdot \times`, `\sqrt{…}` → `√(…)`, `\frac{a}{b}` → `(a)/(b)`, and sub/superscripts — single characters (`x_1` → `x₁`) and braced runs whose content is recursively approximated then mapped character-by-character through the Unicode sub/sup tables (unmappable characters stay literal), covering the common shapes `e^{i\pi}` → `eⁱπ`, `e^{-x^2}` → `e⁻ˣ²`, `\int_{-\infty}^{\infty}` → `∫₋∞∞`. Unknown macros pass through raw (nothing is swallowed); `\begin{…}` environments keep the whole block raw, `$$` delimiters included; spans without a math indicator (prose with dollar amounts like `$5 and $10`) stay untouched; `\$` and backtick code spans are protected. Approximation is a text→text pass before structure classification, inline formatting, and theme chrome — it never splits SGR output. The streaming stable prefix retreats while a `$$` block is unclosed; a never-closed block flushes its raw lines.
- HTML blocks now degrade to readable plain text instead of raw tag soup: block-level tags (`div`/`table`/`tr`/`p`/`ul`/`li`/`details`/`summary`/`h1`–`h6`/`br`) become line breaks, other tags (`span`/`kbd`/`img`, …) are stripped with their attribute strings never emitted, `<summary>` content survives as a prefix line, and named entities (`&amp; &lt; &gt; &quot; &#39; &nbsp;`) decode in a single pass after tag stripping (so `&lt;div&gt;` never re-parses). Table cell tags (`td`/`th`, opening and closing) degrade to a single separating space — whitespace runs collapse and segment ends trim — so adjacent cells stay readable (`DB_HOST 192.168.1.53 仅运维`, not `DB_HOST192.168.1.53仅运维`) while `tr` keeps rows on their own lines. Multi-line tags (attributes wrapped across lines, e.g. a multi-line `<img … />`) render within one pass — the streaming stable prefix retreats while the tag is unclosed, and a never-closed tag keeps its raw lines (no data loss). Degradation runs before the inline pipeline outside fenced code, code spans are protected, and tag-free lines pass through byte-identical (`.none` theme included); degraded segments still get full inline formatting and theme chrome.
- Block-level markdown styling is live: `StreamingMarkdownEngine` now consumes `MarkdownRenderOptions.theme` for block chrome — headings (per-level bold/color via `headingStyle(forLevel:)`), table header cells (bold) and all table border/bars (faint), blockquote bars (faint), and code-fence borders (faint) with the language label (faint italic). Styling is applied only as whole-line / whole-cell wraps after padding and truncation, never inside the `padded()`/`truncate()` path, so a truncating cell can never cut an SGR sequence and leak style into subsequent output (pinned by tests: `ansiStripped` of the styled render reproduces the `.none` render, colored table rows stay width-aligned). `MarkdownTheme.none` keeps the pre-theme plain byte stream byte-for-byte; existing golden tests pin the `.none` stream and new goldens cover the styled bytes. Inline formatting (bold/italic/code spans/links) is unchanged.
- `MarkdownTheme` + `MarkdownRenderOptions.theme`: a value-type visual theme for markdown block chrome (heading levels 1–6, table header/borders, blockquote bar, fence borders/language label, task-list markers, and a `code` slot group for upcoming syntax highlighting), built from the new `MarkdownStyle` / `MarkdownSGRAttribute` / `MarkdownSGRColor` SGR primitives. `MarkdownRenderOptions` now defaults to `MarkdownTheme.default`; `MarkdownTheme.none` disables all theme styling and pins the pre-theme plain byte stream.
- `visibleWidth(_:)` and `ansiStripped(_:)` are now public: ANSI-aware terminal-cell width measurement (per grapheme cluster; wide CJK/emoji 2 cells, combining marks 0) and CSI escape stripping. They are the implementations already used by `MultiLineInputState`, `physicalRows(for:width:)`, and `TUI` cursor placement, and replace hand-written duplicates in consumers (e.g. ForgeLoop's rendering helpers).
- `StdoutTerminal.onWriteFailure` and `RawTTY.onRestoreFailure`: optional hooks reporting the failing `errno` for stdout writes and termios restores — the reporting channel for the documented "Terminal.write does not throw" limitation (see `docs/known-limitations.md`).
- `MarkdownEngine.stableRenderedLineCount`: new protocol requirement (with a default implementation returning 0, so existing conformers are unaffected) certifying how many leading lines of the most recent render are immutable under append-only buffer growth — the boundary append-only consumers may safely commit to scrollback. `StreamingMarkdownEngine` reports its stable prefix (complete, promotion-ready source lines; in-progress tables and unclosed fences stay uncertified), `PlainTextMarkdownEngine` reports its newline-terminated lines.
- `TranscriptRenderer.activeStreamingStableLineCount`: the engine-certified immutable prefix of the active streaming block, for feeding `StreamingTranscriptAppendState.consume(transcript:activeRange:stableLineCount:)`.
- `StreamingTranscriptAppendState.consume(transcript:activeRange:stableLineCount:)`: delta computation that commits only settled pre-block lines plus the engine-certified stable prefix of the streaming block. The printed watermark never rewinds while the transcript only grows, so already-printed lines are never re-emitted — the worst case is a delayed line, never a duplicate.
- MinimalAIApp `/demo` catalog gains `soak` (`Examples/Fixtures/markdown-long-fence-soak.md`): a >100-line document wrapped in a single code fence (table-shaped rows, code snippets, CJK) that keeps the streaming stable prefix at zero until the closing fence, so the entire block previews through the committed region under the full-redraw fallback. The new `Examples/MinimalAIApp/pty_soak_long_fence.py` PTY soak streams it, resizes the terminal mid-stream (24x80 → 30x100), and asserts a live preview across the resize, exactly-once settling in fixture order, and no re-emission after completion (TASK-29).

### Fixed
- Pasting multi-line text into a raw-mode consumer no longer fires key bindings for each embedded newline (pasting into an Enter-to-submit input used to submit immediately). `InputPipeline` has parsed bracketed-paste markers since it was introduced — `ESC[200~` enters aggregation, `ESC[201~` emits one `.paste(String)` event — but the library never wrote the `ESC[?2004h` enable sequence, so terminals never wrapped pasted content and the paste path was dead code: pasted bytes arrived as bare keystrokes and every `\r`/`\n` decoded as `.enter`. `RawTTY.enter()` now writes `ESC[?2004h` through the same best-effort, isatty-guarded stdout channel as the kitty keyboard push, and `restore()` writes `ESC[?2004l`. Terminals without bracketed-paste support (notably Terminal.app) absorb both sequences silently and keep the previous bare-keystroke behavior.
- Ctrl+J is now decodable as its own key: `KeyParser` no longer collapses the LF byte (0x0A) into Enter. Both `parseCharacter` and `parseByte` previously mapped 0x0D and 0x0A to `.enter`, making Ctrl+J indistinguishable from Enter for binding consumers; 0x0A now flows through the regular Ctrl-letter path and decodes as `.character("J")` + `.ctrl` (0x0A + 0x40 = 'J'). CR (0x0D) still decodes as plain `.enter`. The AppKit bridge (`AppKitEventAdapter`) is intentionally unchanged: NSEvent `keyDown` events carry modifier flags directly, so its lineFeed/LF mapping to `.enter` stays as-is (the byte-stream ambiguity it mirrors does not exist there).
- Table cells now render inline markdown instead of literal markers: `**bold**`, `` `code` ``, links, and bare URLs inside `| … |` cells go through the same inline pipeline as paragraphs (previously `tableRow` emitted the raw cell text, so `**DeepSeek**` printed with visible asterisks and the marker characters also inflated column widths). Cells are formatted before width/padding, relying on the ANSI/OSC-aware `visibleWidth`, and truncation is now escape-aware: `fittingPrefix` copies CSI/OSC sequences whole instead of cutting mid-sequence, and a truncated styled span gets a closing `ESC[0m` before the truncation indicator so styling never leaks into neighboring cells. Verified by new cell-formatting and styled-truncation tests.
- Append-only streaming no longer duplicates committed lines when mid-stream re-renders change earlier lines. `StreamingTranscriptAppendState.consume(transcript:activeRange:)` assumed the streaming block's rendered lines are append-only (only the last line may change), but `StreamingMarkdownEngine` re-renders earlier lines as constructs grow — streaming tables flip between raw pipe text and box drawing, column widths widen as rows arrive, unclosed code fences hold their chrome open. Once a printed "completed" line changed, the common-prefix logic re-emitted it; once the transcript shrank below the printed watermark, the clamp reset made every subsequent update re-emit the entire transcript (a 65-line streamed table fixture produced 1675 appended lines; headings and tables appeared dozens of times in scrollback). Committing is now driven by the engine-certified stable prefix: the new `MarkdownEngine.stableRenderedLineCount` (surfaced as `TranscriptRenderer.activeStreamingStableLineCount`) marks how many leading render lines are immutable under append-only growth, and the new `consume(transcript:activeRange:stableLineCount:)` commits exactly those, holding in-progress tables/fences back until they settle. Verified: line-by-line and multi-chunk replays of table/fence/CJK fixtures and the garble-regression corpus now append every transcript line exactly once, and the stable prefix survives the engine's 64KB stable-cache reset unchanged (new `StreamingStableCommitTests`).
- Streaming markdown rendering no longer garbles the terminal when a frame fills the screen and the content changes mid-frame. Two independent defects compounded in the inline-anchor diff path of `TUI` (`renderInline` / `renderInlineCommittedLive`): (1) the per-line erase loop (`ESC[2K` + `\r\n` × tail rows) pushed a trailing `\n` past the bottom row on full-screen frames, scrolling the terminal and ejecting already-committed prefix lines into scrollback (lost lines); (2) the subsequent `ESC[nA` repositioning did not account for that scroll, so the repainted tail was drawn one row too high — permanently shifting the runtime's screen model from the real terminal (duplicated/reordered/garbled output that never self-corrected). The diff path now rewinds to the diff start row and erases to end-of-screen with a single `ESC[0J` (no `\n`, no scroll; emitted only when the previous frame actually had content below the diff start, so first-render output stays byte-identical — no clear) before repainting in place; `VirtualTerminal` gained the matching ED 0 (`ESC[0J`) interpretation. Reproduced deterministically by a two-frame minimal test and a 5434-frame full-pipeline replay (TranscriptRenderer → ScreenLayoutRenderer → TUI) against a scrollback-tracking terminal oracle — all frames now match the oracle exactly.
- `StreamingMarkdownEngine` no longer accumulates phantom blank lines when snapshots land exactly on a line boundary, and streaming tables no longer degrade to raw pipe-delimited text in the final render. Three promotion-boundary defects: (1) the trailing-`""`-strip guard only fired when the unstable remainder was non-empty, so a snapshot ending exactly on `\n` permanently froze a blank line per promoted boundary (a 10-line minimal table streamed per-character ended at 17 lines); (2) `stableAdvance` had no lookahead for an isolated table header — the header was promoted as plain text before the divider arrived, after which the table could never form; (3) the streaming-table retreat was skipped when the remainder was empty, so header+divider were promoted once the first data row landed. The strip is now unconditional (with the final boundary blank restored on `isFinal`, keeping streamed finals byte-identical to one-shot static renders), an isolated header-shaped last line retreats one line, and the trailing-table retreat also runs on boundary-aligned snapshots. Verified: per-character / multi-chunk replays of a complex fixture (headings, nested lists, fenced code, wide tables) converge line-for-line with the static render at every chunk granularity tested (1/2/3/5/7/11).
- `TUI.terminalWidth` / `TUI.terminalHeight` reads are now thread-safe. The stored dims were written under a lock by `updateTerminalSize(width:height:)` but read unsynchronized everywhere (including render passes), so concurrent resizes and renders raced on plain `Int` storage — only ever a stale value in practice, but undefined behavior formally. The properties are now lock-backed computed getters over private storage, guarded by a dedicated leaf lock (`renderLock → lock → dimsLock` strict order, no reentrancy, no ABBA). Cross-field width/height snapshots are not atomic (unchanged semantics). Verified with a new mixed-lane concurrency test under ThreadSanitizer.
- A `blockEnd` arriving with no open block is now ignored instead of appending its content at the end of the transcript. Previously, a late `blockEnd` racing in after a `blockCancel` (e.g. an aborted assistant reply) went through the no-active-block lenient path and rendered its final text after the `[cancelled]` marker. `blockUpdate`'s implicit block adoption (legacy no-`blockStart` usage) is preserved; the change only affects stray/late `blockEnd` events.
- `VirtualTerminal` now honors the ECMA-48 "parameter value 0 means use the default" contract in its motion commands: `ESC[0A`/`ESC[0B`/`ESC[0C`/`ESC[0D` and empty-slot forms like `ESC[;A` previously moved by 0 cells (a no-op) instead of the default 1; `ESC[0G`, `ESC[0L`, and `ESC[0M` likewise map 0 to the default of 1. `KeyParser`'s modifier extraction already treated a 0 modifier slot as "no modifiers" — now pinned by tests.
- The wide-scalar table behind `visibleWidth(_:)` was refreshed to Unicode 16.0: emoji from Unicode 14/15/16 blocks (U+1FA70 onward, e.g. 🫠 U+1FAE0, 🩷 U+1FA77) previously measured 1 cell where terminals render 2, and East Asian wide additions (Yijing hexagram symbols, U+32FF square era name REIWA, trigrams) were missed. Previously wide code points keep their width (additions only), so existing layout is unaffected.
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
