# Harness File Index

This index groups the GoStop HALO / LLM coding harness files by operating role.

Use this file when starting a new task, creating an orchestrator session, or auditing whether a change has enough contract and evidence coverage.

## 1. Start Here

| File | Role | When to Read |
| --- | --- | --- |
| `AGENTS.md` / `agents.md` | Project-level agent rules, roles, logging, workflow, skills registry. | Always at session start or when behavior expectations are unclear. |
| `docs/README.md` | Docs layout and HALO operating file map. | When locating docs or deciding where a new artifact should live. |
| `docs/llm_coding_harness_training.md` | Training/overview of generation, validation, and feedback harness. | When explaining or teaching the harness. |
| `docs/harness_file_index.md` | This index. | When deciding which harness file to use. |

## 2. Orchestrator Layer

| File | Role | When to Read |
| --- | --- | --- |
| `docs/runbooks/orchestrator_agent_flow.md` | Defines the orchestrator agent mission, states, risk classification, owner lanes, delegation, and stop conditions. | First file for orchestrator-agent sessions. |
| `docs/orchestrator_prompt_template.md` | Copyable prompt for starting a Codex session as the HALO orchestrator, plus specialist prompt skeleton. | When opening a new orchestrator thread/session. |
| `docs/orchestrator_board.md` | Orchestrator queue, decision log, and handoff notes. | When checking current orchestration state. |
| `agent_sync_board.md` | Multi-agent implementation board for Agent 1-4 state, blockers, validation, and contract questions. | When work spans multiple agents or lanes. |
| `multi_agent_operating_guide.md` | Worktree/session split, merge order, agent prompts, and parallel operating rules. | Before running multiple agents in parallel. |

## 3. HALO Operating Loop

Required loop:

```text
RTM -> Contract Gate -> Delegation -> Implementation -> E2E Evidence -> Loopback Log
```

| File | Role | When to Read / Update |
| --- | --- | --- |
| `docs/runbooks/halo_operating_flow.md` | Mandatory HALO loop and done criteria. | Before medium/high-risk work. |
| `docs/rtm.md` | Requirement traceability matrix from user intent to contract, implementation, validation, and evidence. | Create/update before implementation and after closeout. |
| `docs/change_contract_template.md` | Template for pre-state, trigger, post-state, evidence, scope, and validation. | Copy into `docs/agent_tasks/active/` or a durable contract doc before editing. |
| `docs/gate_checklist.md` | Approval/waiver/rejection log. | Before implementation, contract change, E2E waiver, or final merge/finish. |
| `docs/e2e_evidence_log.md` | Artifact-backed PASS evidence index. | After validation passes or when E2E is waived. |
| `docs/loopback_log.md` | Failure classification and return-phase/layer decisions. | Before another edit after validation failure. |
| `project_progress.md` | Request-level work log: skills, files touched, validation, outcome. | At work start/end per `AGENTS.md` logging rule. |

## 4. Durable Contract Documents

| File | Owner Lane | Role |
| --- | --- | --- |
| `multiplayer_contract.md` | Agent 1 / Core Engine | Authority state, commands, events, rejection semantics, stateVersion/actionId/playerId contract. |
| `room_protocol.md` | Agent 2 / Backend | Room/session/websocket lifecycle and transport protocol. |
| `multiplayer_ui_flow.md` | Agent 3 / UI | Product route, screen flow, UI states, multiplayer shell behavior. |
| `multiplayer_test_scenarios.md` | Agent 4 / Test | Scenario matrix, validation lens, and multiplayer regression coverage. |
| `multiplayer_test_scenario_runbook.md` | Agent 4 / Test | How to run multiplayer scenarios and interpret outputs. |

## 5. Agent Prompt and Task Archives

| File / Directory | Role |
| --- | --- |
| `agent_prompts/agent1_core_prompt.md` | Base prompt for Core Engine / Game Authority lane. |
| `agent_prompts/agent2_backend_prompt.md` | Base prompt for Backend / Lobby / Reconnect lane. |
| `agent_prompts/agent3_ios_prompt.md` | Base prompt for iOS Multiplayer Client / UX lane. |
| `agent_prompts/agent4_test_prompt.md` | Base prompt for Debugging / Test Scenarios / Observability lane. |
| `docs/agent_tasks/active/` | Current task contracts, active prompts, and temporary working notes. |
| `docs/agent_tasks/archive/` | Completed round/task prompt archive. |
| `matgo_multiplayer_multi_agent_plan.md` | Earlier multi-agent planning artifact. |

## 6. Skill Source Index

| File / Directory | Role |
| --- | --- |
| `docs/skills/README.md` | Index of copied local and registry skill sources. |
| `docs/skills/installed/gostop-test-reliability__gostop-test-reliability.md` | Runtime anomaly diagnosis, requirement-to-contract gate, LOOPBACK rule. |
| `docs/skills/installed/gostop-ui-playability__gostop-ui-playability.md` | UI contract gate, animation parity, render-probe evidence. |
| `docs/skills/installed/game-external-test-agent__game-external-test-agent.md` | External E2E validation agent, false-success prevention. |
| `docs/skills/installed/gostop-game-builder__gostop-game-builder.md` | GoStop implementation and validation workflow. |
| `docs/skills/registry/project_management__agent_orchestration__agent_orchestration.md` | Registry skill for sync boards and agent start prompts. |
| `docs/skills/registry/project_management__project_logger__project_logger.md` | Progress logging skill source. |
| `docs/skills/registry/game_development__test_agent_sync__test-agent-sync.md` | Test-agent synchronization when contracts change. |

## 7. Validation Harness Code

| File / Directory | Role |
| --- | --- |
| `tests/test_agent/test_scenarios.py` | Single-player rule/scoring regression scenarios. |
| `tests/test_agent/multi_test_scenario.py` | Unified multiplayer scenario entrypoint. |
| `tests/test_agent/multiplayer_runner.py` | Multiplayer validation runner. |
| `tests/test_agent/multiplayer_ui_auto_play.py` | Two-simulator UI autoroute runner and render/evidence probes. |
| `tests/test_agent/multiplayer/` | Multiplayer scenario models, validators, fixtures, socket transport, artifact helpers. |
| `tests/test_agent/main.py` | Bridge client entrypoint. |
| `tests/test_agent/ai_player.py` | Automated play decision agent. |
| `scripts/run_multiplayer_cli_two_player_smoke.py` | CLI room/bootstrap/heartbeat/gap smoke harness. |
| `scripts/cleanup_artifacts.sh` | Artifact cleanup helper. |
| `test_artifacts/README.md` | Artifact retention and directory policy. |

## 8. Reports, Logs, and Evidence

| File / Directory | Role |
| --- | --- |
| `test_artifacts/` | Runtime validation outputs, screenshots, timelines, summaries, replays. |
| `docs/reports/anomaly_report.md` | Archived anomaly report sample/report. |
| `docs/logs/build_output.log` | Archived build log. |
| `tests/test_agent/artifacts/test-agent-sync-report.md` | Test-agent sync evidence report. |

## 9. Practical Read Order

### New product change

1. `docs/orchestrator_prompt_template.md`
2. `docs/runbooks/orchestrator_agent_flow.md`
3. `docs/rtm.md`
4. relevant contract document
5. `docs/change_contract_template.md`
6. `docs/gate_checklist.md`
7. relevant skill source
8. validation runner or scenario file
9. `docs/e2e_evidence_log.md`
10. `docs/loopback_log.md` if validation fails

### Debugging a failed run

1. failing `test_artifacts/**/summary.md`
2. relevant timeline/action log/screenshot
3. `docs/loopback_log.md`
4. `docs/skills/installed/gostop-test-reliability__gostop-test-reliability.md`
5. relevant contract document
6. matching scenario runner

### Starting multiple agents

1. `multi_agent_operating_guide.md`
2. `agent_sync_board.md`
3. `docs/orchestrator_board.md`
4. owner contract documents
5. agent prompt files or generated specialist prompt

## 10. Maintenance Rules

- Add every new harness control file to this index.
- Do not move root-level contract files without updating `agent_sync_board.md` and this index.
- For medium/high-risk changes, do not mark work done unless RTM, gate, evidence, and loopback state are consistent.
- Keep artifacts in `test_artifacts/`; keep reusable instructions in `docs/`; keep active contracts or prompts in `docs/agent_tasks/active/`.
