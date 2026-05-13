# SemVer and API Stability Policy

Date: 2026-05-11  
Applies to: `ForgeLoopTUI` Swift Package, version `0.2.0` and onward  
Policy version: 1.0

---

## 1. SemVer mapping for Swift packages

We follow [Semantic Versioning 2.0.0](https://semver.org) with Swift-specific clarifications.

| Bump | When |
|------|------|
| **MAJOR** (`X.0.0`) | Any breaking change to a **Stable** public API (see §3). Behavioral changes that violate documented invariants. Removal of a deprecated API after the deprecation window. |
| **MINOR** (`0.Y.0`) | New **Stable** or **Provisional** APIs. New enum cases on `CoreRenderEvent` or `Key`. New fields on `ScreenLayout` with default values. New convenience methods on `HybridRenderAdapter`. Evolution of **Provisional** APIs. |
| **PATCH** (`0.0.Z`) | Bug fixes that do not change documented behavior. Documentation corrections. Performance improvements with no observable semantic change. Test-only changes. |

---

## 2. What counts as a breaking change

### 2.1 Source-breaking (always MAJOR)

- Renaming or removing a `public` type, function, property, or enum case marked **Stable**.
- Changing the signature of a `public` function (parameter labels, types, return type).
- Adding a new requirement to a `public` protocol marked **Stable**.
- Removing a default implementation from a `public` protocol extension.
- Changing a `struct` to a `class` or vice versa.
- Removing a `public` initializer.

### 2.2 Behavior-breaking (MAJOR if documented invariant is violated)

- Changing the output of `ScreenLayoutRenderer` for the same `ScreenLayout` + `ScreenLayoutConfig` in a way that contradicts the documented partition-priority budget policy.
- Changing `TUI.render(frame:)` so that committed/live diff semantics no longer match the documented contract.
- Changing `TranscriptRenderer.applyCore(_:)` so that event ordering produces different `transcriptLines` for the same input sequence.
- Changing ANSI width calculations so that CJK/emoji widths differ from the documented rules.

### 2.3 NOT breaking (MINOR or PATCH)

- Adding a new `public` type, function, or property.
- Adding a new enum case with a `@unknown default` compatible pattern (Swift enum exhaustiveness).
- Adding new fields to a `struct` with compiler-generated memberwise init, **provided** a manual `init` with the old parameter set is preserved.
- Changing **Internal-detail** APIs (no SemVer protection).
- Changing the internal algorithm of `ANSIParser` without changing observable `Terminal` output.
- Performance improvements that do not change observable frame content or ordering.

---

## 3. Stability tiers

See `docs/public-api-surface.md` for the per-type stability assignment.

| Tier | SemVer protection | Deprecation required? |
|------|-------------------|----------------------|
| **Stable** | Full MAJOR protection | Yes, minimum 1 MINOR window |
| **Provisional** | MINOR evolution allowed | Preferred, but not required |
| **Internal-detail** | None | Not applicable |
| **Deprecated** | None (scheduled removal) | Already deprecated |

### 3.1 Provisional API evolution gate

Before evolving a **Provisional** API (adding methods, changing behavior, or graduating to Stable), the following must be satisfied:

1. **Real-world evidence**: at least 2 distinct callers or a documented pain point.
2. **Contract test coverage**: new/changed behavior has dedicated tests; existing contract tests stay green.
3. **Cross-repo gate**: `./Scripts/cross-repo-gate.sh --quick` passes.

Example: `PromptHistory` (`docs/prompt-history-api-decision.md`) follows this gate. Capacity limits, dedup, persistence, and multi-group history are all deferred until evidence and tests materialize.

---

## 4. Deprecation policy

1. **Deprecation window**: A **Stable** API must be marked `@available(*, deprecated, message: "...")` for at least **one MINOR release** before removal.
2. **Deprecation message** must include:
   - The replacement API name.
   - The version in which the API was deprecated.
   - The earliest version in which it may be removed.
3. **Example**:
   ```swift
   @available(*, deprecated, message: "Use applyCore(_:) with CoreRenderEvent instead. Deprecated in 0.2.0; will be removed in 0.4.0.")
   public func apply(_ event: RenderEvent) { ... }
   ```
4. **Deprecated APIs are not tested in new test suites**. Existing tests keep them green until removal.

---

## 5. Compatibility test requirements

Before every release, the following test filters must pass:

```bash
# 1. All library tests
swift test

# 2. Component / layout regression
swift test --filter ScreenLayoutRendererTests
swift test --filter ComponentTests
swift test --filter LayoutBudgetTests

# 3. Runtime regression
swift test --filter CommittedLiveRenderTests
swift test --filter TUITests

# 4. Input regression
swift test --filter InputPipelineTests
swift test --filter KeyParserTests

# 5. ANSI / terminal regression
swift test --filter ANSIParserTests
swift test --filter VirtualTerminalTests

# 6. Bridge regression (M6+)
swift test --filter HybridRenderAdapterTests

# 7. Integration / smoke
swift test --filter CapabilityEndToEndTests
swift test --filter PublicAPISmokeTests
```

If any of these fail, the release is **blocked**.

---

## 6. Pre-1.0 exception

Until `1.0.0`, MINOR releases may contain breaking changes to **Provisional** APIs without a MAJOR bump. **Stable** APIs still require MAJOR bumps even pre-1.0.

After `1.0.0`, all **Stable** APIs require MAJOR bumps. **Provisional** APIs may still evolve in MINOR releases.

---

## 7. Changelog format

Every release must include a `CHANGELOG.md` entry with these sections:

```markdown
## [0.X.Y] — YYYY-MM-DD

### Added
- New APIs and features.

### Changed
- Behavioral changes that are not breaking.

### Deprecated
- APIs scheduled for removal.

### Removed
- APIs that reached end of deprecation window.

### Fixed
- Bug fixes.

### Security
- Security-related fixes.
```

---

## 8. Related documents

- `docs/public-api-surface.md` — Per-type stability assignment
- `docs/release-checklist.md` — Step-by-step release validation
- `docs/integration-guide.md` — Consumer guidance on version selection
