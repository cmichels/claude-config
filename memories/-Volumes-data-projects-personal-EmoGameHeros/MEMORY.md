# EmoGameHeros Project Memory

## Codebase Overview
- 105 source files, ~21.5K lines, 67 test files
- Phaser 3 + TypeScript + Vite game project
- 10 completed ralph phases, feature/ralph10 branch
- User: kuda (collaborative, keyboard-centric workflow)

## Architecture Patterns
- **Services**: Singleton pattern via class + exported const (ContentService, SaveService, GameStateManager, DeathHandler)
- **EventBus**: Global Phaser.Events.EventEmitter, events defined in EventNames.ts
- **Entities**: Player, Enemy, Boss all implement Damageable interface
- **CombatSystem**: Per-scene state via scene.data.set(), hitbox/hurtbox overlap
- **Scenes**: Template Method pattern - BaseLevelScene and BaseCinematicScene
- **Content**: JSON bundles in content/, loaded via ContentService manifest

## Key Files by Size (review priority)
- LevelBackgroundRenderer (971), Enemy (920), CinematicC4Scene (868)
- CinematicC6/C7 (~740 each), GarageEnvironmentBuilder (714)
- DialogueBox (695), Player (682), HUDScene (673), Boss (632)

## Review Infrastructure
- Review process: `reviews/REVIEW_PROCESS.md`
- Review template: `reviews/REVIEW_TEMPLATE.md`
- First review: `reviews/2026-02-22-review.md` (43 findings)
- GitHub issues #31-#41 created for P0/P1 findings
- Review labels: review:bug, review:leak, review:dry, review:magic, review:smell, review:pattern, review:infra + priority:p0-p3

## Known Technical Debt
- Cinematic scenes (C1-C7): ~340 lines of duplicated patterns
- Entity texture generation inflates entity files (~700 lines total)
- ContentService has repetitive loader/indexer pattern
- AudioSystem uses setInterval instead of Phaser timer
- No typed event payloads on EventBus
