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
