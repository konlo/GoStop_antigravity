<!--
Copied skill source for documentation.
Original path: /Users/najongseong/.codex/skills/gostop-test-reliability/SKILL.md
Source group: installed
Skill name: gostop-test-reliability
Original relative directory: gostop-test-reliability
-->

---
name: gostop-test-reliability
description: Diagnose and fix GoStop runtime anomalies during automated play validation. Use when tests generate anomaly_report.md or rule_checklist_report.md, when play/select/go/stop commands fail due to phase or turn-step mismatches, when setup/pause/replay state transitions cause flaky automation, or when a GoStop change needs a requirement-to-contract gate, failure loopback, traceable validation evidence, and regression-safe repair across engine, CLI, simulator bridge, or Python test-agent code.
---

# GoStop Test Reliability

Stabilize automated GoStop validation runs by triaging anomaly reports, enforcing state-safe action dispatch, and verifying recovery behavior.

## Quick start
1. Write a short change contract before editing:
- requirement summary
- expected state transition
- authoritative fields that must change
- evidence that proves success
- exact regression command(s)
2. Read `StopGo/anomaly_report.md` and extract failing check IDs, last action, and last state.
3. Correlate with `StopGo/game_log.txt` and engine traces from `logs` API.
4. Classify failure type using `references/failure-patterns.md`.
5. Apply minimal, high-impact fixes to state guards in:
- `StopGo/test_agent.py`
- `GoStop/GoStop/APIEngine.swift`
- `GoStop/GoStop/GameEngine.swift`
- `GoStop/GoStop/Models/GameState.swift`
6. Re-validate with `scripts/compile_test_agent.sh` and targeted command-flow checks.

## Workflow
### 0) Requirement-to-contract gate
- Do not start code edits until the failure or requested behavior is expressed as a state contract.
- Include:
- pre-state: phase, turn step, current player, pending choice, room/session state when relevant
- trigger: command, accepted action, snapshot, bridge request, or test-agent dispatch
- post-state: exact fields expected to change and fields that must not regress
- evidence: summary/report/log/probe line that will prove success
- loopback target: engine, API/bridge, test agent, simulator UI, transport, or probe
- If any field is unknown, inspect artifacts or code first instead of guessing.

### 1) Parse anomaly context
- Capture these fields from `anomaly_report.md`:
- Issue
- Context
- Not Satisfied checks
- Last Action Sent
- Last Response Received
- Current Game State summary
- Treat failure as state/timing first, logic second.
- When a failure follows a code edit, compare the new failure signature against the contract before applying another fix.

### 2) Enforce command safety in test agent
- Dispatch `play/select/stop` only when all are true:
- `gamePhase == "playing"`
- `currentPlayerIndex == 0`
- step matches expected command
- `isPaused == false`
- Add recovery flow for transient states:
- `setup/gameOver` -> `start`
- `isPaused == true` -> `resume`
- `isReplayMode == true` -> `quit`
- Mark hard FAIL only after recovery attempts are exhausted.

### 3) Verify engine/API state guards
- Confirm API rejects invalid phase/step actions with explicit error text.
- Confirm `startNewGame` fully resets round state and pending animation/match fields.
- Confirm pause/resume does not leak stale UI/replay state into active gameplay.
- Confirm `quitToMenu` returns state to clean `setup`.

### 4) Preserve invariants
- Keep deck checks mandatory:
- 48 total cards
- month 1..12 each has 4 cards
- each month has 4 unique image slots
- Keep action acceptance checks mandatory:
- `start` invalid when already active
- `go/stop` valid only at decision step
- `play/select` valid only on player turn and correct step

### 5) LOOPBACK rule
- If validation fails, do not immediately patch another layer.
- Classify the first failing transition:
- contract wrong: revise expected behavior and rerun without code edits
- probe wrong: fix test/probe and rerun the same build
- environment stale: clean relaunch/reinstall/restart server before code edits
- engine/API wrong: patch core transition or rejection rule only
- UI/bridge propagation wrong: patch mapping/snapshot/transport wiring only
- Stop after two unsuccessful edits in the same layer; broaden diagnosis before continuing.

### 6) Validate and report
- Run syntax validation for `test_agent.py`.
- Re-run targeted flow and ensure no repeat of the same anomaly signature.
- Include at least one real command output or artifact path in the final evidence.
- Summarize:
- root cause
- exact changed files
- validation evidence
- residual risks

## Notes
- Prefer small, state-aware fixes over broad rewrites.
- Do not suppress errors; convert flaky timing errors into explicit recovery rules.
- Keep debug logs actionable by including phase, turn step, and current player in failure messages.
