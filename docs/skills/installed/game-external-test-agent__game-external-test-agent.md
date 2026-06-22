<!--
Copied skill source for documentation.
Original path: /Users/najongseong/.codex/skills/game-external-test-agent/SKILL.md
Source group: installed
Skill name: game-external-test-agent
Original relative directory: game-external-test-agent
-->

---
name: game-external-test-agent
description: Build and harden external socket-based game test agents that run outside the game process, poll current state, choose the next action, and generate reproducible anomaly and improvement evidence. Use when users ask to create or improve an out-of-process test agent, validate play/select/go/stop flows, debug phase or turn-step mismatches, gather logs/replay/diff artifacts, prevent mock-only false success, or define real E2E validation contracts for engine, simulator bridge, multiplayer, or UI repair work.
---

# Game External Test Agent

## Quick Start

1. Confirm the bridge contract, required actions, and pass/fail evidence.
2. Define the validation contract: seed, starting state, controlled player, expected transition, artifact outputs.
3. Generate a starter external agent with `scripts/scaffold_external_agent.py`.
4. Implement state-safe dispatch rules before gameplay heuristics.
5. Run socket validation and collect artifacts.
6. Use anomaly evidence to patch engine or agent guards.

## Workflow

1. Read `references/gostop-bridge-contract.md` for request/response fields and required actions.
2. Write the E2E contract before scaffolding or editing:
- target behavior
- seed/setup requirements
- state fields to poll
- action sequence or decision policy
- required artifacts
- clear PASS and FAIL conditions
3. Scaffold a starting agent:

```bash
python3 scripts/scaffold_external_agent.py --profile gostop --output /tmp/external_gostop_agent.py
python3 -m py_compile /tmp/external_gostop_agent.py
```

4. Start the game bridge (project-side):

```bash
swift run GoStopTestCLI --socket
```

5. Run the external agent (separate terminal):

```bash
python3 /tmp/external_gostop_agent.py --host 127.0.0.1 --port 8080 --rounds 50
```

6. For integrated validation, read and run commands in `references/validation-playbook.md`.

## State-Safe Dispatch Rules

Enforce all guards before sending `play/select/go/stop`:
- `gamePhase == "playing"`
- `isPaused == false`
- `isReplayMode == false`
- `currentPlayerIndex` matches the external controlled player
- `turnStep` matches the intended command

Apply recovery commands when needed:
- `setup` or `gameOver` -> `start`
- `isPaused == true` -> `resume`
- `isReplayMode == true` -> `quit`

Treat state and timing failures before strategy failures.

## Evidence Requirements

Produce artifacts that explain failures without re-running:
- Last action sent
- Last response payload
- Condensed state summary (phase, step, player, pause/replay flags)
- Checklist status (`state_polling_available`, `action_guard`, `decision_reachability`, `runtime_error_free`)
- Action volume and error-code distribution
- Replay/log/diff pointers
- Environment contract: device/simulator IDs, ports, transport URL, build path, seed

When possible, write:
- `anomaly_report.md`
- `rule_checklist_report.md`
- `improvement_report.md`

## Repair Loop

1. Reproduce with fixed seed and same rounds.
2. Isolate first failing transition from logs and state diff.
3. Patch the smallest guard or transition rule.
4. Re-run socket mode and in-process parity checks.
5. Stop only when repeated runs are stable.

## False Success Prevention

- Do not accept a mock-only PASS for behavior that depends on live bridge, transport, simulator, animation, or device networking.
- Require at least one real E2E run when the user-visible behavior crosses process boundaries.
- Treat missing artifacts as inconclusive, not PASS.
- If the test agent changes during a fix, re-run one known-good baseline to prove the harness still detects ordinary success.
- If a failure disappears after environment reset, record it as environment/session failure rather than engine success.
