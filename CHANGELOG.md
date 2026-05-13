# Changelog

All notable changes to this project will be documented in this file.

Format and section names follow `docs/semver-and-api-stability.md` (§7).

## [0.2.0] — 2026-05-13

### Added
- `TUI.cursorPositioningMode` now exposes `.relative` (default) and `.marker` (physical-row + `CHA`) cursor positioning strategies for different terminal reliability needs.
- `Viewport` and `MultiLineInputState.setViewport(_:)` provide visual-row aware `moveUp` / `moveDown` navigation for wrapped multi-line input.
- AppKit bridge surfaces were expanded with `AppKitEventAdapter`, `HybridObservableState`, and `PanelMetadataProviding` bridge helpers.
- Baseline performance gates were codified for `LiveBudgetPlanner`, `MultiLineInputState`, and `KeyResolver` hot paths.

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
