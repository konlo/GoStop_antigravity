# UI Design Document

## 2026-03-03 Update: Player Info + Cumulative Win Score

### Goal
- Persist winning points across games and expose the current cumulative winning points next to player information.

### Layout Decision
- Reuse existing `score` element slot in each player area (`opponent`, `player`).
- Extend score panel content:
  - Line 1: `playerName` + `승리누적 <points>`
  - Line 2: round score (`score` prefix from layout config)
- Use red text for `승리누적` for visibility against green table/background tones.

### Architectural Constraints
- Keep game-rule calculation in `Core`.
- Keep UI rendering in `Views`.
- Do not move score/turn rule decisions into SwiftUI layout code.

### Data Flow
1. `GameManager` records winner points at game end (`STOP`, `총통`, fallback win).
2. `GameManager` updates in-memory `cumulativeWinScores`.
3. `GameAreaViews` reads `gameManager.cumulativeWinScore(for:)` and renders alongside player name.

### Persistence File
- Filename: `gostop_cumulative_win_scores.json`
- Location: app `Documents` directory (fallback: current working directory)
- Payload:
  - `version`
  - `totals` (`[playerName: accumulatedWinningPoints]`)

## 2026-03-03 Update: Player Area Sort Button Removal

### Goal
- Remove the debug-only `Sort` button from the player area to keep gameplay UI clean.

### Decision
- Delete the `PlayerAreaV2` inline `Sort` button block.
- Keep underlying slot/sort manager logic unchanged for internal hand ordering behavior.

### Architectural Constraints
- UI-only change in `Views`.
- No changes to game rules or engine behavior in `Core`.

## 2026-03-04 Update: Triple Seolsa End Popup Gating

### Goal
- When a round ends by triple Seolsa (3뻑), show an explicit end-cause event popup first, then reveal the game-ended overlay.

### Layout/Interaction Decision
- Add a dedicated special-event popup mapping for the engine log line containing `reached Triple Seolsa`.
- During `gameState == .ended` with `gameEndReason == .threeSeolsa`, defer ended overlay rendering while special-event popup is active or queued.
- Keep existing special popup queue animation/duration pipeline unchanged.

### Architectural Constraints
- UI-only handling in `GameView`.
- No rule/engine state transition logic moved into SwiftUI layout layer.
