## Iteration 1 — First-Launch Night-Day Starter

- Date: 2026-03-03
- Type: Rule Adjustment
- Affected Area: Starter selection at game start (`GameManager`, `GameView`, `RuleConfig`, `rule.yaml`)
- Original Behavior: `startGame()` always set `currentTurnIndex = 0` (Player 1 fixed starter).
- New Behavior: `startGame(initialTurnIndex:)` accepts an optional starter override, and only the first manual start in app lifecycle applies 밤일낮장 to compute the initial starter.
- Design Conflict: No
- Decision Rationale: Keep game-engine impact minimal by preserving default behavior and injecting the new rule only from the UI first-launch path.
- Approved By: User request (2026-03-03)

## Iteration 2 — Shake-Only Score Multiplier

- Date: 2026-03-03
- Type: Rule Adjustment
- Affected Area: Endgame score multiplier and bomb handling (`PenaltySystem`, `GameManager`, `rule.yaml`, test scenarios)
- Original Behavior: Final multiplier used `2^(shakeCount + bombCount)`, and bomb execution incremented both `bombCount` and `shakeCount`.
- New Behavior: Final multiplier uses only `2^shakeCount`, and bomb execution increments only `bombCount`.
- Design Conflict: No
- Decision Rationale: User requested that final score multiplier applies to declared shakes only, not bombs.
- Approved By: User request (2026-03-03)

## Iteration 3 — Bomb Increments ShakeCount, Multiplier Remains ShakeCount-Only

- Date: 2026-03-04
- Type: Rule Adjustment
- Affected Area: Bomb turn bookkeeping and bomb regression scenarios (`GameManager`, `PenaltySystem`, `tests/test_agent/test_scenarios.py`)
- Original Behavior: Bomb execution incremented only `bombCount`, while final multiplier was still computed from `shakeCount` only.
- New Behavior: Bomb execution increments both `bombCount` and `shakeCount`, and final multiplier remains defined only by `shakeCount` (`2^shakeCount`).
- Design Conflict: No
- Decision Rationale: User explicitly requested restoring bomb -> shakeCount accumulation while preserving shakeCount-only multiplier definition.
- Approved By: User request (2026-03-04)

## Iteration 4 — Triple Seolsa Instant Win (10 Points)

- Date: 2026-03-04
- Type: Rule Adjustment
- Affected Area: Endgame condition and Seolsa rule contract (`GameManager`, `RuleConfig`, `rule.yaml`, `tests/test_agent/test_scenarios.py`)
- Original Behavior: Seolsa only incremented `seolsaCount` (and optional Seolsa penalty pi transfer) without any direct win condition.
- New Behavior: When a player reaches `special_moves.seolsa.instant_win_count` (configured as 3), the round ends immediately with fixed score `special_moves.seolsa.instant_win_score` (configured as 10).
- Design Conflict: Yes
- Decision Rationale: User explicitly requested introducing a new win condition (3 Seolsa) with fixed winning score 10, which intentionally extends existing endgame rules.
- Approved By: User request (2026-03-04)
