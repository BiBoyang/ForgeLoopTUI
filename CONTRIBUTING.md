# Contributing to ForgeLoopTUI

Thanks for your interest in contributing.

## Getting Started

### Prerequisites

- Swift 6.0+
- macOS 14+
- Xcode 16+ (for AppKit bridge examples)

### Build

```bash
swift build
```

### Test

```bash
swift test
```

For focused testing during development, see [TESTING.md](TESTING.md) for subsystem-specific test filters.

## Code Conventions

- **Language mode**: Swift 6 (strict concurrency checking enabled).
- **Access control**: Prefer `internal` by default. Only expose types and methods as `public` when they are part of the documented stable API surface.
- **Documentation**: Public API must have English `///` doc comments. Internal implementation comments may be in Chinese; contributions to internal docs in either language are welcome.
- **Thread safety**: Types that cross concurrency domains should be `Sendable`. Types with internal mutable state should use a lock and `@unchecked Sendable`.
- **Naming**: Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/). Prefer clarity over brevity.
- **No `print` in production code**: Use structured logging or diagnostics callbacks instead.
- **No `fatalError` / `preconditionFailure`**: Except to enforce design invariants in initializers (e.g., `KeyStroke` rejecting `.paste`).

## PR Workflow

1. **Discuss first**: For new features, open an issue to discuss design before writing code.
2. **Branch**: Create a feature branch from `main`.
3. **Write tests**: All new behavior must include tests. Bug fixes should include a regression test.
4. **Run the full suite**: `swift test` must pass.
5. **Update CHANGELOG**: Add your changes under `[Unreleased]`.
6. **Keep commits focused**: Each commit should address one logical change.

## Review Expectations

- **Corner cases**: Tests should cover boundary conditions (empty input, negative values, maximum-length strings).
- **Backward compatibility**: Changes to public API must follow the [SemVer policy](docs/semver-and-api-stability.md).
- **No breaking changes** to stable API surface without prior discussion and a migration path.

## Public API Surface

The authoritative list of public types organized by stability tier is in [docs/public-api-surface.md](docs/public-api-surface.md). Before adding new public API, consult that document.

## Documentation

- **Public API**: `///` doc comments required in English.
- **Architecture**: See [docs/module-dataflow-and-dependency-map.md](docs/module-dataflow-and-dependency-map.md).
- **Integration**: See [docs/integration-guide.md](docs/integration-guide.md).

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
