# Ralph7 Research — Level 1 Gameplay Integration

> Gathered 2026-02-21. Use when creating .ralph7/ infrastructure.

## Key Finding: Integration, Not Greenfield

All core systems are fully built. The gap is wiring them together:
- `updateBonJoviAI()` in `BonJoviAttacks.ts` line 379 — fully coded, NEVER CALLED
- `BossArenaScene.update()` line 112 — only updates player, boss is inert
- `Boss.ts` — no movement logic, no `update()` method
- `Level1Scene.ts` — 17-line stub, needs zone hooks
- `DemonWhisperSystem.ts` — complete, never instantiated in any level
- `BaseLevelScene.create()` — ignores zoneId from GameOverScene retry data
- `level_1.json` — all 15 enemies have `waveId: null`

## Proposed Phase Structure (17 tasks, 6 phases)

- **Phase 0**: Boss Arena AI (wire updateBonJoviAI, add boss movement, integration test)
- **Phase 1**: Zone Enhancement (zone atmosphere, background themes, DemonWhisperSystem)
- **Phase 2**: Death/Victory Flow (zone checkpoint, reward pipeline, boss death test)
- **Phase 3**: Wave Gating (wave-gated enemies, pre-boss gate, difficulty scaling)
- **Phase 4**: C7 Send-off (expand dialogue, Level 1 intro title)
- **Phase 5**: Integration Testing (full flow test, lifecycle audit, content validation)

Dependency: Phase 0 first → Phase 2 depends on 0 → Phase 5 last. Others independent.

## Derek's Level1.md Design Tensions

1. Derek describes rocks + bow staff + distortion guitar. Code has light/heavy attacks + spells.
   Resolution: map existing attacks to narrative context.
2. Derek says "nu-metal followers" and "Jets fans". Code has jock/poser/scenester.
   Resolution: existing enemy types serve the role adequately.
3. Derek wants subway chase with speed-based scaling — NOT in current scope.
   Would require new scene/mechanic. Deferred or separate ralph round.

## Iteration Estimate

108 max, ~65-75 expected. Most tasks are wiring/testing existing code.

## Critical Files

- `src/scenes/BossArenaScene.ts` — boss AI wiring
- `src/entities/Boss.ts` (605 lines) — needs movement
- `src/entities/attacks/BonJoviAttacks.ts` (~400 lines) — AI exists, never called
- `src/scenes/Level1Scene.ts` (17 lines) — needs zone hooks
- `src/scenes/BaseLevelScene.ts` (342 lines) — zone checkpoint fix
- `content/levels/level_1.json` (451 lines) — wave gating
- `src/systems/DemonWhisperSystem.ts` — wire into Level 1
- `src/systems/BackgroundRenderer.ts` — zone-themed backgrounds
