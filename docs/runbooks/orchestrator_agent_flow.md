# Orchestrator Agent Flow

This runbook defines the orchestrator agent for the GoStop HALO harness.

The orchestrator does not replace specialist agents. It controls the work loop so every meaningful change follows:

```text
RTM -> Contract Gate -> Delegation -> Implementation -> E2E Evidence -> Loopback Log
```

## Mission

The orchestrator agent is responsible for:
- turning user requests into RTM rows
- deciding whether a contract gate is required
- selecting the correct specialist agent or skill lane
- generating bounded task prompts
- checking whether validation evidence is sufficient
- deciding whether failure requires loopback instead of more edits
- updating project progress and handoff state

The orchestrator should not directly implement risky product changes unless the user explicitly asks for a single-agent direct implementation.

## Required Inputs

Before deciding the next action, read:
- `docs/rtm.md`
- `docs/gate_checklist.md`
- `docs/e2e_evidence_log.md`
- `docs/loopback_log.md`
- `agent_sync_board.md`
- `docs/runbooks/halo_operating_flow.md`
- relevant contract documents:
  - `multiplayer_contract.md`
  - `room_protocol.md`
  - `multiplayer_ui_flow.md`
  - `multiplayer_test_scenarios.md`

Read only the relevant contract files for the request. Avoid loading everything by default.

## Operating States

| State | Meaning | Required Output |
| --- | --- | --- |
| `Triage` | New request received; risk and owner unclear. | RTM row or direct low-risk answer. |
| `Contract Pending` | Behavior is not yet expressed as a contract. | Change contract draft. |
| `Gate Pending` | Human approval or waiver is required. | Gate checklist row. |
| `Delegation Ready` | Contract and gate are sufficient. | Agent prompt or direct implementation plan. |
| `Implementing` | Specialist agent or current Codex is editing. | Scope guard and expected evidence. |
| `Validation Pending` | Implementation exists but evidence is missing. | Validation command and artifact target. |
| `PASS` | Evidence satisfies the contract. | E2E evidence log row and progress entry. |
| `Loopback` | Validation failed or contract drift appeared. | Loopback log row and revised next phase. |
| `Deferred` | Work is out of current scope. | RTM status and reason. |

## Decision Rules

### Risk Classification

Low risk:
- documentation-only changes
- narrow copy edits
- non-behavioral cleanup

Medium risk:
- test harness changes
- UI layout or animation changes
- local engine behavior changes covered by scenarios

High risk:
- multiplayer protocol changes
- stateVersion / actionId / playerId semantics
- simulator/device/network behavior
- changes that can produce mock-only success

Medium/high-risk work must use RTM, contract gate, and evidence logging.

### Owner Selection

Use this lane map:

| Work Type | Primary Lane | Contract Owner |
| --- | --- | --- |
| Rule, score, turn flow, authority payload | Agent 1 / Core Engine | `multiplayer_contract.md` |
| Room, websocket, reconnect, session lifecycle | Agent 2 / Backend | `room_protocol.md` |
| SwiftUI, product route, animation, UI state | Agent 3 / UI | `multiplayer_ui_flow.md` |
| Scenario, runner, artifact, regression evidence | Agent 4 / Test | `multiplayer_test_scenarios.md` |
| Cross-cutting planning, RTM, gates, loopback | Orchestrator | `docs/rtm.md` and HALO docs |

If a request spans multiple lanes, the orchestrator must split it into separate RTM rows or explicit sub-prompts.

## Orchestration Loop

1. **Triage the request**
   - Identify risk level.
   - Identify owner lane.
   - Decide whether direct answer, direct edit, or delegated work is appropriate.

2. **Create or update RTM**
   - Add a `Req ID`.
   - Set status to `Contract Pending` or `Gate Pending`.
   - Link expected contract and validation surface.

3. **Draft the contract**
   - Use `docs/change_contract_template.md`.
   - Put active contracts under `docs/agent_tasks/active/` unless a durable contract file is better.

4. **Open or record the gate**
   - For medium/high risk, update `docs/gate_checklist.md`.
   - If approval is implicit from the user's direct request and the change is doc-only, record it.

5. **Generate delegation prompt**
   - Use `docs/orchestrator_prompt_template.md`.
   - Keep scope narrow.
   - Include required files, forbidden files, validation command, and evidence output.

6. **Review result**
   - Check changed files against allowed scope.
   - Check validation evidence against the contract.
   - Update `docs/e2e_evidence_log.md` on PASS.

7. **Loopback on failure**
   - If validation fails, update `docs/loopback_log.md`.
   - Do not allow another edit until the first bad transition is classified.

8. **Close the request**
   - Update `docs/rtm.md` status.
   - Update `project_progress.md`.
   - Leave next action if not complete.

## Prompt Generation Rules

Every delegated prompt must include:
- role
- Req ID
- contract file
- allowed files
- forbidden files
- validation command
- artifact path
- reporting format

Do not ask a specialist agent to "figure everything out". The orchestrator must hand off bounded work.

## Stop Conditions

Stop and ask the user before proceeding when:
- the gate is `Pending` or `Rejected`
- the request needs a contract change outside the current owner lane
- real E2E is required but unavailable
- the same layer failed twice without a new diagnosis
- the next step would require destructive cleanup or broad refactor

## Completion Criteria

An orchestrated task is complete only when:
- RTM status is `PASS` or `Deferred`
- gate is approved or waived
- evidence is logged or waiver is recorded
- loopback log exists for failed validation runs
- specialist handoff is reflected in `agent_sync_board.md` when multiple agents are involved
- `project_progress.md` records the final outcome
