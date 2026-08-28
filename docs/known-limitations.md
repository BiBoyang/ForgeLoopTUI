# Known Limitations

Deliberate API-shape limitations that are documented rather than fixed, with
their rationale and the available mitigation. Entries here are candidates for
a future major release.

## `Terminal.write(_:)` does not throw

`Terminal.write(_:)` (and therefore every render path in `TUI`) cannot report
write failures through the type system: a failed `write(2)` on stdout is
silently truncated at the source. Making it `throws` would cascade through
the entire rendering API, so the signature stays.

Mitigation (failure reporting channels):

- `StdoutTerminal.onWriteFailure` — called with the failing `errno` when a
  stdout write cannot complete.
- `RawTTY.onRestoreFailure` — called with the failing `errno` when restoring
  termios via `tcsetattr` fails inside `restore()` (which cannot throw
  because it also runs from `deinit`).

Both hooks are optional; when unset, behavior matches previous releases
(silent failure).
