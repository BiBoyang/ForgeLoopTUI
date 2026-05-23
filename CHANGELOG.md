# Changelog

All notable changes to this project will be documented in this file.

Format and section names follow `docs/semver-and-api-stability.md` (§7).

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
