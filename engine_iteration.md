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
