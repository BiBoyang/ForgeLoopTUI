# ForgeLoopTUI Long Transcript Fixture

This fixture is used for manual smoke testing of long terminal output behavior.

## Goals

- verify scrollback is preserved
- verify long output does not look noisy or duplicated
- verify wrapped lines remain readable
- verify CJK and ASCII mixed content stay aligned well enough for terminal use

## Sample Lines

Line 001 — The quick brown fox jumps over the lazy dog.
Line 002 — Streaming output should feel stable and monotonic.
Line 003 — A user prompt should appear once, not repeatedly.
Line 004 — Completed assistant lines should not be re-appended.
Line 005 — Partial lines should remain mutable until finalized.
Line 006 — This fixture intentionally includes enough lines to scroll.
Line 007 — Hello from ForgeLoopTUI.
Line 008 — 你好，世界。这里是一行中英混排文本。
Line 009 — The terminal should preserve prior content in scrollback.
Line 010 — Lorem ipsum dolor sit amet, consectetur adipiscing elit.
Line 011 — Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
Line 012 — Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.
Line 013 — Duis aute irure dolor in reprehenderit in voluptate velit esse cillum.
Line 014 — Excepteur sint occaecat cupidatat non proident, sunt in culpa.
Line 015 — This line is intentionally short.
Line 016 — This line is intentionally much longer so that narrower terminals may wrap it across more than one physical row during manual smoke testing.
Line 017 — Keep watching for duplicated prompts or repeated headers.
Line 018 — Keep watching for ANSI escape garbage appearing in visible output.
Line 019 — Keep watching for dropped trailing lines at stream end.
Line 020 — Wide chars: 表格、宽字符、终端、滚动、历史记录。
Line 021 — ASCII 0123456789012345678901234567890123456789
Line 022 — Symbols !@#$%^&*()_+-=[]{};':",./<>?
Line 023 — Monotonic append is better than noisy full-frame replay.
Line 024 — Retained-mode redraw should not erase scrollback unexpectedly.
Line 025 — If a line becomes stable, it may be appended once.
Line 026 — If a line is still partial, it should remain pending.
Line 027 — The footer can update separately from transcript history.
Line 028 — This fixture keeps going.
Line 029 — This fixture keeps going.
Line 030 — This fixture keeps going.
Line 031 — This fixture keeps going.
Line 032 — This fixture keeps going.
Line 033 — This fixture keeps going.
Line 034 — This fixture keeps going.
Line 035 — This fixture keeps going.
Line 036 — This fixture keeps going.
Line 037 — This fixture keeps going.
Line 038 — This fixture keeps going.
Line 039 — This fixture keeps going.
Line 040 — This fixture keeps going.
Line 041 — This fixture keeps going.
Line 042 — This fixture keeps going.
Line 043 — This fixture keeps going.
Line 044 — This fixture keeps going.
Line 045 — This fixture keeps going.
Line 046 — This fixture keeps going.
Line 047 — This fixture keeps going.
Line 048 — This fixture keeps going.
Line 049 — This fixture keeps going.
Line 050 — This fixture keeps going.
Line 051 — This fixture keeps going.
Line 052 — This fixture keeps going.
Line 053 — This fixture keeps going.
Line 054 — This fixture keeps going.
Line 055 — This fixture keeps going.
Line 056 — This fixture keeps going.
Line 057 — This fixture keeps going.
Line 058 — This fixture keeps going.
Line 059 — This fixture keeps going.
Line 060 — This fixture keeps going.
Line 061 — This fixture keeps going.
Line 062 — This fixture keeps going.
Line 063 — This fixture keeps going.
Line 064 — This fixture keeps going.
Line 065 — This fixture keeps going.
Line 066 — This fixture keeps going.
Line 067 — This fixture keeps going.
Line 068 — This fixture keeps going.
Line 069 — This fixture keeps going.
Line 070 — This fixture keeps going.
Line 071 — This fixture keeps going.
Line 072 — This fixture keeps going.
Line 073 — This fixture keeps going.
Line 074 — This fixture keeps going.
Line 075 — This fixture keeps going.
Line 076 — This fixture keeps going.
Line 077 — This fixture keeps going.
Line 078 — This fixture keeps going.
Line 079 — This fixture keeps going.
Line 080 — This fixture keeps going.

## Manual Notes

- Try a normal terminal first.
- Then resize to a short height and review the scrollback behavior.
- Then verify wrapped long lines and mixed CJK lines still look acceptable.
