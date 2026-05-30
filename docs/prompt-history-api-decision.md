# PromptHistory API Decision Record

Date: 2026-05-11
Status: Accepted
Scope: `ForgeLoopTUI/Input/PromptHistory.swift`

## 1. What It Is

`PromptHistory` is a minimal input-history navigation primitive for terminal UIs. It provides up/down arrow navigation through previously committed input strings.

It carries **no business semantics** — no conversation-id, no session-key, no persistence, no grouping. It is purely a navigation data structure.

## 2. Frozen API (Current)

These five API surface points are frozen for the current development phase:

| API | Signature | Semantics |
|-----|-----------|-----------|
| `init()` | `public init()` | Empty history, index at "current editing" position |
| `commit(_:)` | `mutating func commit(_ text: String)` | Insert non-empty text at position 0 (most recent), reset index to current |
| `prev()` | `mutating func prev() -> String?` | Move index toward older entries; `nil` when at oldest boundary |
| `next()` | `mutating func next() -> String?` | Move index toward newer entries; `nil` when back at current |
| `reset()` | `mutating func reset()` | Set index to current (-1), preserving all entries |
| `isAtCurrent` | `var isAtCurrent: Bool` | `true` when index is at current editing position |

Conforms to: `Sendable`, `Equatable`.

## 3. Out of Scope (This Phase)

The following enhancements are explicitly deferred. They are NOT blocked forever, but they are NOT expected in the current milestone cycle:

| Enhancement | Rationale for deferral |
|-------------|----------------------|
| Capacity limit (e.g. max N entries) | No evidence yet that unbounded growth is a problem in CLI usage; adding eviction policy now would be speculative |
| Deduplication (consecutive identical entries) | Behavior preference varies by consumer; library should not enforce a policy without demonstrated need |
| Draft recovery (session persistence) | Persistence semantics (where, when, what format) belong to the app layer, not the navigation primitive |
| Multi-group / per-conversation history | Adds grouping key complexity; no consumer has asked for this |
| Callback / delegate on history mutation | Over-engineering for a 5-method struct; consumers can observe externally |
| `count` / `isEmpty` / `subscript` | Not needed for current nav-only usage; can be added as convenience accessors in a MINOR release |

## 4. When the API Can Evolve

A change to the `PromptHistory` API surface (new methods, new fields, behavioral changes) must satisfy **all three** of the following triggers:

### Trigger A — Real-world evidence

At least one of:
- Two or more distinct callers (e.g. `ForgeLoopCli` + one other consumer) request the same capability.
- A documented pain point (issue, review, or post-mortem) that cannot be solved without API change.

### Trigger B — Contract test coverage

- The new or changed behavior must have dedicated tests in `Tests/ForgeLoopTUITests/Input/PromptHistoryTests.swift`.
- Existing contract tests must remain green (no regression).

### Trigger C — Cross-repo gate

- `./Scripts/cross-repo-gate.sh --quick` must pass with the change.
- If the change touches `ForgeLoopCli` call-sites, the PR description must include the gate result.

## 5. SemVer Classification

| Attribute | Value |
|-----------|-------|
| Current tier | **Provisional** (per `docs/public-api-surface.md`) |
| Breaking changes | Not expected; if unavoidable, require MAJOR bump even pre-1.0 |
| Additive changes (new methods, convenience accessors) | Allowed in MINOR releases with migration notes |
| Behavioral changes to existing frozen methods | Treated as breaking; require MAJOR bump |
| Internal refactors (e.g. storage change) | PATCH if behavior is identical and tests confirm |

After `1.0.0`, `PromptHistory` is expected to graduate to **Stable** if no significant evolution has occurred for at least 2 MINOR releases.

## 6. Design Rationale

- **Why a struct, not a class?** Value semantics match the usage pattern: history is owned by one input loop, copied for state snapshots if needed, and has no shared mutable identity.
- **Why `Equatable`?** Enables state diffing in test assertions and UI reconciliation without additional infrastructure.
- **Why `Sendable`?** Allows safe capture in `@MainActor` and structured concurrency contexts; the struct contains only `[String]` and `Int`, both `Sendable`.
- **Why no `count` or `subscript`?** The current navigation model (prev/next relative to an internal cursor) doesn't expose absolute indexing. Consumers navigate by relative movement only. Adding absolute access would require defining whether `index` is part of the public contract, which is a design decision worth its own review.

## 7. Related Documents

- `docs/public-api-surface.md` — Per-type stability assignment
- `docs/semver-and-api-stability.md` — SemVer policy and evolution rules
- `docs/migration-guide-for-forgeloopcli.md` — Migration record (InputHistory → PromptHistory)
