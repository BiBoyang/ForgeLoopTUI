# TODO

## Next Up

- Add a second example focused on Markdown presentation quality, separate from the current stability/smoke example.
- Improve terminal-friendly Markdown rendering for common structures:
  - headings
  - blockquotes
  - lists
  - fenced code blocks
  - tables
- Decide which helper APIs should remain public in `ForgeLoopTUI` and which should become internal-only.
- Add a small public-API smoke test target or workflow so releases verify consumer usability without `@testable import`.
- Expand fixture coverage with more real-world samples:
  - very long transcript
  - mixed CJK + ASCII
  - wide tables
  - multiline tool summaries
- Document expected output patterns for the examples in `TESTING.md`.

## Notes

- Keep `ForgeLoopTUI` focused on reusable terminal transcript/rendering primitives.
- Keep app-specific layout and agent adaptation logic in `ForgeLoop`, not in this library.
