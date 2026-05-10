# TODO

## Current Focus

Bring the remaining reusable TUI infrastructure out of `ForgeLoopCli` and into
`ForgeLoopTUI` without moving app-specific Agent logic into the library.

Current status:

- Done: core runtime, terminal abstraction, virtual terminal, ANSI pipeline,
  transcript pipeline, markdown pipeline, input pipeline, component primitives.
- Done (slice 1, 2026-05-10): `TerminalSize/getTerminalSize` and UTF-8 erase
  tty flag helpers are now library-owned in `ForgeLoopTUI`; `ForgeLoopCli`
  switched to `ForgeLoopTUI.KeyEvent` + `InputReader`; app-local
  `TUIRunner.swift` was removed.
- Remaining gap: `ForgeLoopCli` still owns duplicate input/runtime glue and a
  thin bottom-area layout layer that should live in `ForgeLoopTUI`.

## Ordered Migration TODO

### 1. Input and Terminal Foundation

1. Add `Sources/ForgeLoopTUI/Terminal/TerminalSize.swift`
   - Move `TerminalSize` and `getTerminalSize()` out of
     `ForgeLoop/Sources/ForgeLoopCli/Layout.swift`.
   - Keep the API terminal-generic and free from app vocabulary.
2. Add `Sources/ForgeLoopTUI/Input/TTYFlags.swift` or extend
   `Sources/ForgeLoopTUI/Input/RawTTY.swift`
   - Move `hasUTF8EraseFlag(_:)` and `withUTF8EraseFlag(_:)` out of
     `ForgeLoop/Sources/ForgeLoopCli/TUIRunner.swift`.
3. Extend `Sources/ForgeLoopTUI/Input/InputReader.swift` only if needed
   - Confirm whether `ForgeLoopCli` still needs injectable read sources for
     tests; if yes, add that extension in the library rather than reviving a
     parallel CLI-only reader.
4. Update `ForgeLoop/Sources/ForgeLoopCli/CodingTUI.swift` ✅
   - Replace local `TUIRunner` usage with `ForgeLoopTUI.InputReader` +
     `ForgeLoopTUI.TUI`.
   - Switch all key handling to `ForgeLoopTUI.KeyEvent`.
5. Delete `ForgeLoop/Sources/ForgeLoopCli/TUIRunner.swift` ✅
   - Remove the duplicate `KeyEvent`, `InputSource`, `StandardInputSource`,
     `KeyParser`, `TUIRunner`, and helper flag functions from the app layer.

### 2. Layout Extraction

6. Add `Sources/ForgeLoopTUI/Components/ScreenLayout.swift`
   - Extract reusable layout model from
     `ForgeLoop/Sources/ForgeLoopCli/Layout.swift`.
   - Keep only generic regions such as header, transcript, status, prompt, and
     pinned/live hints.
7. Add `Sources/ForgeLoopTUI/Components/ScreenLayoutRenderer.swift`
   - Rebuild the current `LayoutRenderer` on top of `ComposedFrame`,
     `LayoutBudget`, and existing component adapters.
   - Do not copy the current CLI renderer verbatim if it still returns raw
     `[String]` only.
8. Update `Sources/ForgeLoopTUI/Components/Adapters/TranscriptComponent.swift`
   - Ensure it can participate cleanly in the extracted screen layout path.
9. Update `Sources/ForgeLoopTUI/Components/Adapters/TextInputComponent.swift`
   - Either align it with `TextInputState.render(...)` semantics or replace it
     with a more useful adapter for prompt-row rendering.
10. Update `ForgeLoop/Sources/ForgeLoopCli/CodingTUI.swift`
    - Replace direct `Layout` / `LayoutRenderer` usage with
      `ScreenLayoutRenderer` and `TUI.render(frame:)`.
11. Delete `ForgeLoop/Sources/ForgeLoopCli/Layout.swift`
12. Delete `ForgeLoop/Sources/ForgeLoopCli/LayoutRenderer.swift`

### 3. Orchestrator Cleanup

13. Refactor `ForgeLoop/Sources/ForgeLoopCli/CodingTUI.swift`
    - Keep only app orchestration, Agent subscriptions, slash command flow,
      model picker flow, footer-notice policy, and app-specific status text.
    - Remove reusable terminal plumbing after the library extraction lands.
14. Re-evaluate `InputHistory` in
    `ForgeLoop/Sources/ForgeLoopCli/CodingTUI.swift`
    - If it becomes generic after the layout/input migration, move it later as
      `PromptHistory`; otherwise keep it in the app.

### 4. Verification and Docs

15. Update tests in both repositories
    - `ForgeLoopTUI`: input, terminal, component, and integration coverage for
      the newly extracted paths.
    - `ForgeLoop`: focused CLI integration tests proving the app still composes
      the library instead of re-implementing it.
16. Update documentation after each slice
    - `docs/source-structure-and-reuse-refactor-plan.md`
    - `docs/macos-tui-framework-development-plan.md`
    - `README.md` if public API or module discovery changes

## Explicitly Stay In ForgeLoopCli

- `Sources/ForgeLoopCli/AgentEventRenderAdapter.swift`
- `Sources/ForgeLoopCli/PromptController.swift`
- `Sources/ForgeLoopCli/SlashCommandRegistry.swift`
- `Sources/ForgeLoopCli/AttachmentStore.swift`
- `Sources/ForgeLoopCli/CredentialStore.swift`
- `Sources/ForgeLoopCli/ModelStore.swift`
- App-specific parts of `Sources/ForgeLoopCli/CodingTUI.swift`

## Notes

- Keep `ForgeLoopTUI` focused on reusable terminal runtime, transcript,
  markdown, input, and composition primitives.
- Keep app-specific layout semantics, Agent adaptation, model switching, auth,
  and attachment payload policy in `ForgeLoop`.
- Prefer small extraction slices: library landing first, app adoption second,
  deletion third.
