## Usage Log — 2026-03-03

- **Instruction**: "앱 첫 실행 1회에만 밤일낮장으로 선 결정 규칙 추가"
- **Plan**: Add a rule-config entry and a minimal start-turn override hook, then apply the rule only in the manual first-launch entry point.
- **Actions**:
  - Added `starter` config model and YAML entries.
  - Extended `GameManager.startGame` with optional initial turn override and implemented night/day starter resolver.
  - Applied one-time first-launch consumption in `GameView.startManualGame` via `UserDefaults`.
  - Added regression tests for override and night/day starter decision.
- **Outcome**: Success

## Usage Log — 2026-03-03

- **Instruction**: "마지막 점수 계산은 shake에 대해서만 배수 적용, rule/test scenario 동기화"
- **Plan**: Remove bomb contribution from multiplier logic, update rule comments/config values, and align affected scenarios/assertions.
- **Actions**:
  - Updated `PenaltySystem` multiplier source from `shake+bomb` to `shake` only and changed formula label to `Shake(xN)`.
  - Updated bomb turn handling to increment only `bombCount`.
  - Updated `rule.yaml`, `GoStop/Resources/rule.yaml`, and `tests/test_agent/rule.yaml` bomb multiplier note/value.
  - Synced scenario expectations (`bomb_and_steal`, `score_formula`, `bomb_as_shake_multiplier`, `endgame_conditions`, shake-stacking docs).
  - Rebuilt `GoStopCLI` and validated targeted scenario set with the rebuilt executable.
- **Outcome**: Success

## Usage Log — 2026-03-04

- **Instruction**: "폭탄은 shakecount를 올리되, 배수 계산은 shakecount만 사용"
- **Plan**: Restore bomb -> shakeCount increment in engine while keeping multiplier formula shakeCount-only, then synchronize impacted bomb scenario assertions.
- **Actions**:
  - Updated `GameManager.handleBombPlay` so bomb execution increments `shakeCount` together with `bombCount`.
  - Kept scoring computation in `PenaltySystem` based only on `shakeCount` and clarified comments to avoid bombCount term confusion.
  - Synced `tests/test_agent/test_scenarios.py` bomb regression expectation (`shakeCount` on bomb turn).
  - Rebuilt `GoStopCLI` and validated targeted scenarios (`5`, `36`, `24`, `31`) against rebuilt binary.
- **Outcome**: Success

## Usage Log — 2026-03-04

- **Instruction**: "한 사람이 뻑을 3번 하면 승리 조건으로 넣어주고 점수는 10점으로 승리할 수 있도록 해줘"
- **Plan**: Add a new Seolsa-based instant-win endgame branch with configurable threshold/score, then synchronize rule YAML and Seolsa regression scenarios.
- **Actions**:
  - Extended `SeolsaRule` contract with `instant_win_count` and `instant_win_score`.
  - Added `threeSeolsa` game-end reason and immediate end handling in `GameManager.checkEndgameConditions`.
  - Implemented fixed-score end resolution path that sets finalScore/money transfer and summary formula for triple Seolsa wins.
  - Synced `rule.yaml`, `GoStop/Resources/rule.yaml`, and `tests/test_agent/rule.yaml` with `instant_win_count: 3`, `instant_win_score: 10`.
  - Added `scenario_verify_triple_seolsa_instant_win` and registered it in the scenario runner.
  - Rebuilt `GoStopCLI` and validated Seolsa scenario set (`--filter seolsa`) including the new triple-Seolsa case.
- **Outcome**: Success
