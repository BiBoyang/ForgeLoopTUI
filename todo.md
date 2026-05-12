# TODO

## Current Focus

Ongoing maintenance and stabilization of `ForgeLoopTUI` as a reusable TUI framework.

### Next Slice Queue (Post-1.0)

1. **Performance gate discipline**
   - Keep `PerformanceBaselineTests` / `PerformanceGateTests` snapshots current.
   - Document accepted regressions (if any) before merge.
   - **SOP**：退化处置流程见 `docs/post-m7-maintenance-protocol.md` §7（复现→归因→决策→记录）。
   
2. **Optional cleanup (strictly non-blocking)**
   - Revisit `AgentEventRenderAdapter` semantic cleanup only when event vocabulary stabilizes.

3. **Post-1.0 deferred items**
   - DocC catalog and hosted API reference
   - Swift Package Index integration
   - Additional example packages

## Explicitly Stay In ForgeLoopCli

- `Sources/ForgeLoopCli/AgentEventRenderAdapter.swift`
- `Sources/ForgeLoopCli/PromptController.swift`
- `Sources/ForgeLoopCli/SlashCommandRegistry.swift`
- `Sources/ForgeLoopCli/AttachmentStore.swift`
- `Sources/ForgeLoopCli/CredentialStore.swift`
- `Sources/ForgeLoopCli/ModelStore.swift`
- App-specific parts of `Sources/ForgeLoopCli/CodingTUI.swift`

## Notes

- Keep `ForgeLoopTUI` focused on reusable terminal runtime, transcript, markdown, input, and composition primitives.
- Keep app-specific layout semantics, Agent adaptation, model switching, auth, and attachment payload policy in `ForgeLoop`.
