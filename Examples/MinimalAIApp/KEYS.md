# MinimalAIApp Keybindings & Interaction Manual

This document mirrors the keybinding registry built in
`Sources/MinimalAIApp/main.swift` via `MinimalAIApp.defaultKeybindings()`.
It is the source of truth for what users can type while the app is running.

For library-level concepts (`KeyStroke`, `KeySequence`, `KeybindingRegistry`,
`KeyResolver`), see `docs/integration-guide.md` §7 in the ForgeLoopTUI repo.

---

## Mode

`MinimalAIApp` runs `TUI` with:

- `liveBudget: 4`
- `liveBudgetMode: .physicalRows` — long / wrapped input auto-settles older
  lines into committed history.
- `cursorPositioningMode: .marker` — hardware cursor uses CHA-based absolute
  positioning so IME candidate windows align precisely.

The input buffer is a `MultiLineInputState` with a `Viewport` synchronised
to the available width every render, so `Up` / `Down` walk visual rows when
the input wraps.

---

## Single-key commands

| Key            | Action            | Notes |
|----------------|-------------------|-------|
| `Enter`        | Submit            | Sends the buffer to the AI provider. |
| `Backspace`    | Delete back       | Standard. |
| `Delete`       | Delete forward    | Standard. |
| `←` / `→`      | Move cursor       | Crosses line boundaries. |
| `↑` / `↓`      | Move cursor       | Visual-row-aware when wrapped; `↑` at the top / `↓` at the bottom is a no-op. |
| `Home`         | Line start        | Moves to start of current logical line. |
| `End`          | Line end          | Moves to end of current logical line. |
| `Esc`          | Clear / Cancel    | Cancels current streaming response if any, otherwise clears the input buffer. |

## Readline-style chord keys (Ctrl-letter)

| Chord     | Action            | Notes |
|-----------|-------------------|-------|
| `Ctrl-O`  | Insert newline    | Use this when you need a multi-line prompt — `Enter` always submits. |
| `Ctrl-A`  | Line start        | Mirrors `Home`. |
| `Ctrl-E`  | Line end          | Mirrors `End`. |
| `Ctrl-U`  | Kill to line start| Deletes from cursor to start of line. |
| `Ctrl-K`  | Kill to line end  | Deletes from cursor to end of line. |
| `Ctrl-P`  | History prev      | Walk backward through submitted prompts. |
| `Ctrl-N`  | History next      | Walk forward through history (or back to current draft). |
| `Ctrl-C`  | Interrupt         | Cancels current streaming and exits the app. |

## Multi-key chords

| Chord              | Action  | Notes |
|--------------------|---------|-------|
| `Ctrl-X` `Ctrl-S`  | Submit  | Emacs-style "save buffer" alias for `Enter`. |

Chord prefixes wait up to 500 ms for the next key. If you press `Ctrl-X`
and never follow up, the prefix is released as a normal passthrough event
(no action is dispatched).

---

## Resolver semantics

- Plain typed characters not bound above pass through to the input state
  and become part of the buffer.
- `Bracketed paste` events always pass through; large pastes never trigger
  chord prefix matching.
- Up to one buffered chord prefix exists at any time; pressing a key that
  doesn't continue the chord releases the prefix as passthrough and retries
  the new key as a fresh sequence.

---

## Adding your own bindings

`MinimalAIApp.defaultKeybindings()` calls `try registry.register(_:action:)`
once per command. To extend the keymap:

1. Add a new case to `enum AppCommand`.
2. Handle it in `apply(command:)`.
3. Register a `KeySequence` for it in `defaultKeybindings()`.

The registry rejects conflicts at registration time:

- `RegistrationError.duplicate` — the same `KeySequence` was registered twice.
- `RegistrationError.prefixConflict` — a binding would shadow / extend another.
- `RegistrationError.containsPaste` — `Key.paste` slipped into a sequence
  (the public `KeyStroke` initializer also traps on `.paste`).

See `docs/integration-guide.md` §7 for a worked example.
